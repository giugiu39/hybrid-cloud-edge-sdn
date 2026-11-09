# 02 – Baseline: la Spine-Leaf con lo Spanning Tree di Ryu

Prima di scrivere il mio controller, ho voluto misurare come si comporta la
topologia Spine-Leaf con una soluzione "classica": l'app
`ryu.app.simple_switch_stp_13`, che aggiunge lo Spanning Tree Protocol
(STP, IEEE 802.1D) a un normale switch con MAC learning.

Questi numeri sono il punto di partenza ("prima") con cui confronterò il
controller del progetto ("dopo").

## Perché serve lo STP

La Spine-Leaf contiene degli anelli: per esempio
leaf1 → spine1 → leaf2 → spine2 → leaf1. Un controller che inonda i
broadcast (ARP, frame verso MAC sconosciuti) su tutte le porte li farebbe
girare all'infinito, moltiplicandoli a ogni switch: è il **broadcast storm**,
che in pochi secondi satura link e CPU.

Lo STP risolve il problema costruendo un albero: elegge uno switch come
**root bridge** e blocca le porte che chiuderebbero un anello. Funziona, ma
ha un prezzo: i link bloccati restano inutilizzati.

## Situazione normale

| Switch | Ruolo STP | Porte bloccate |
|--------|-----------|----------------|
| spine1 | root bridge | nessuna |
| spine2 | – | 2 su 3 (verso due leaf) |
| leaf1, leaf2, leaf3 | – | nessuna (root port verso spine1) |

- Tutto il traffico tra leaf passa da **spine1**.
- **spine2 non trasporta dati**: è collegata alla rete da un solo link e
  serve solo come riserva.

### Come lo STP blocca una porta in OpenFlow

Su una porta bloccata Ryu fa due cose (verificato nel sorgente di
`ryu/lib/stplib.py` e con `ovs-ofctl`):

1. imposta i flag `NO_FWD` e `NO_PACKET_IN` sulla porta (`OFPPortMod`);
2. installa una regola a priorità 65534 che scarta tutto ciò che entra da
   quella porta (`in_port=N actions=drop`).

Le BPDU hanno una regola ancora più alta (priorità 65535,
`dl_dst=01:80:c2:00:00:00 → CONTROLLER`).

Verifica pratica: dopo un `pingall`, i contatori delle due regole di drop su
spine2 sono passati da 0 a 45 e 25 pacchetti. Erano broadcast ARP e primi
ICMP che, senza lo STP, avrebbero chiuso un anello.

## Gli esperimenti

### Metodo

- Cronometro: un ping continuo da a1 a srv1, ogni 0,5 s, con l'orario di
  ogni riga:
  `docker exec mn.a1 ping -D -O -i 0.5 10.0.100.1`.
  Il percorso a1 → srv1 (leaf1 → leaf3) passa da spine1.
- Guasto e ripristino di uno switch: `tests/switch_failure.sh`, che elimina
  e ricrea il bridge OVS e stampa l'orario al millisecondo.
- Interruzione = tempo tra l'ultimo ping riuscito prima dell'evento e il
  primo riuscito dopo, calcolato dagli orari.

### Risultati

| Scenario | Interruzione | Esito |
|----------|-------------|-------|
| Cade un solo uplink (leaf1↔spine1) | oltre 6 minuti | nessun recupero |
| Flap dei link di spine1 (giù e subito su) | 26 s | si torna allo stesso albero |
| **spine1 spenta** (bridge eliminato) | **59–66 s** | spine2 diventa root |
| **spine1 riaccesa** | **31 s** | spine1 si riprende la root |

### Cade un solo uplink: la rete non si riprende

Spegnendo il solo link leaf1↔spine1, esisteva ancora una strada:
leaf1 → spine2 → leaf3. Lo STP però non l'ha mai attivata: leaf1 e spine2
sono rimasti isolati per più di 6 minuti, finché non ho riacceso il link.

La spiegazione più probabile è il flag `NO_PACKET_IN` sulle porte bloccate di
spine2. Le BPDU in arrivo da leaf2 e leaf3 raggiungono lo switch (i contatori
salgono), ma non vengono inoltrate al controller. Ryu quindi non scopre che
dietro quelle porte c'è un percorso valido verso la root, e non le riapre
mai. La stessa documentazione di Ryu avverte che `simple_switch_stp_13` può
non funzionare bene con Open vSwitch.

### spine1 spenta: 66 secondi

Le leaf non vedono cadere nessun cavo (le interfacce restano accese) e si
accorgono del guasto solo quando smettono di arrivare le BPDU di spine1.
I tempi sono quelli dello STP classico:

- fino a 20 s di *max age* prima di considerare scaduta la vecchia root;
- 15 s in LISTEN e 15 s in LEARN prima di tornare a inoltrare;
- qualche secondo in più perché a1 rifaccia l'ARP.

Alla fine spine2 diventa root, apre tutte le porte e il traffico passa da
lei.

### spine1 riaccesa: anche la riparazione costa 31 secondi

Appena il bridge di spine1 rientra, annuncia un Bridge ID migliore di quello
di spine2 e viene rieletto root (*preemption*). Per cambiare root in
sicurezza, gli switch riportano le porte in blocco e le riaprono per gradi
(2 × 15 s). Alla fine si torna alla situazione normale, con spine2 di nuovo
inutilizzata.

Sommando guasto e riparazione, un singolo evento è costato circa
**97 secondi di disservizio**.

## Altri comportamenti osservati

**Ryu riaccende le porte spente.** Spegnere le porte con
`ip link set ... down` non basta per simulare un guasto: tornano su da sole.
Ryu modifica lo stato STP delle porte con un `OFPPortMod` la cui maschera
include il bit `PORT_DOWN`, che però non viene mai impostato a 1. Ogni
messaggio riporta quindi la porta in stato amministrativo "acceso". Per questo
lo script di test elimina il bridge invece di spegnerne le porte.

**L'albero cambia da un avvio all'altro.** Ryu costruisce il Bridge ID con
la priorità e il MAC della prima porta dello switch, non con il DPID. I MAC
delle interfacce veth create da Mininet sono casuali, quindi a ogni avvio
cambiano gli spareggi: la porta attiva di spine2 e, a volte, la root stessa.
In più, le priorità di default di `stplib` sono un dizionario condiviso tra
gli switch, quindi la priorità ereditata può dipendere dall'ordine in cui gli
switch si collegano.

**I ping in coda.** Alla ripresa del traffico, i primi ping mostravano
tempi decrescenti a passi di circa 500 ms (2104, 1600, 1096, 592 ms). Non
erano pacchetti lenti: il kernel di a1 li aveva tenuti in coda in attesa
della risposta ARP e li ha spediti tutti insieme appena l'ha ricevuta.

## Cosa mi aspetto dal mio controller

| | STP di Ryu (misurato) | Obiettivo del mio controller |
|---|---|---|
| Uso delle spine | una sola, l'altra di riserva | entrambe in uso |
| Guasto di un uplink | nessun recupero | percorso alternativo in meno di un secondo |
| Guasto di una spine | 59–66 s | percorso alternativo in meno di un secondo |
| Ritorno della spine | 31 s di stop | nessuna interruzione |
| Comportamento | dipende da MAC casuali | deterministico |

Il controller vedrà la topologia con LLDP e conoscerà in anticipo tutti i
percorsi possibili. Così potrà evitare i loop senza bloccare link e reagire
a un guasto reinstallando solo le regole dei flussi colpiti.
