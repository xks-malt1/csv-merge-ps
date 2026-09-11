# csv-merge-ps

Všeobecný PowerShell nástroj na zlúčenie viacerých CSV súborov do jedného.

Súbory sa zlučujú **od najväčšieho po najmenší** podľa počtu záznamov.
Výsledok sa uloží ako `merged_DDMMYYYY.csv` do podpriečinka `vystup`.

Pred zlúčením skript overí, že všetky súbory majú **rovnakú dátovú
štruktúru**. Ak nie, nezapíše nič a vypíše, čo presne sa líši.

## Obsah

| Súbor | Čo robí |
|---|---|
| `Zluc-Csv.ps1` | hlavný skript — zlúčenie a kontrola štruktúry |
| `Zluc-Csv.cmd` | spúšťač na dvojklik |
| `office-script-import-dpd.ts` | Office Script — import zlúčeného CSV do Excelu Online |

## Použitie

1. Stiahni repozitár (Code → Download ZIP) a rozbaľ ho
2. Nakopíruj CSV súbory do priečinka so skriptom
3. Dvojklik na `Zluc-Csv.cmd`

Priamo na `.ps1` neklikaj — Windows ho otvorí v Poznámkovom bloku,
namiesto toho, aby ho spustil.

Predvolene skript pracuje s priečinkom, v ktorom sám leží. Ak chceš iný,
prepíš `$Zdroj` a `$Vystup` v sekcii NASTAVENIA.

## Nastavenia

| Premenná | Predvolené | Význam |
|---|---|---|
| `$Zdroj` | priečinok skriptu | kde sa hľadajú vstupné CSV |
| `$Vystup` | `vystup` | kam sa uloží výsledok |
| `$Oddelovac` | `;` | oddeľovač stĺpcov |
| `$Maska` | `*.csv` | filter súborov, napr. `export*.csv` |
| `$PrisnePoradie` | `$true` | poradie stĺpcov musí sedieť, nielen ich zoznam |
| `$Odstranit` | `@()` | stĺpce na odstránenie z výsledku, podporuje `*` |

## Kontrola štruktúry

Vzorom je najväčší súbor, ostatné sa porovnávajú proti nemu. Skript
hlási tri druhy rozdielov:

- **chýba** — stĺpec je vo vzore, ale v porovnávanom súbore nie
- **navyše** — stĺpec je v súbore, ale vo vzore nie
- **iné poradie** — rovnaké stĺpce, ale na iných pozíciách

Pri akomkoľvek rozdiele sa beh ukončí a nezapíše sa nič.

Porovnávanie ignoruje diakritiku, veľkosť písmen, viacnásobné medzery
a prípadný BOM v hlavičke. Vďaka tomu sadne `Užív. hmotnosť` aj na
`UŽÍV.  HMOTNOSŤ`.

Ak ti prekáža, že rovnaké stĺpce v inom poradí sa berú ako chyba,
nastav `$PrisnePoradie = $false` — dáta sa vtedy preskladajú podľa
vzoru.

## Kódovanie

Vstupy sa kontrolujú na UTF-8 BOM a skript upozorní, ak niektorý súbor
BOM nemá. Nie je to chyba — beh pokračuje ďalej.

Zápis je vynútený cez .NET, takže výstup má BOM vždy: v Windows
PowerShelli 5.1 aj v PowerShelli 7. Bez BOM by Excel pokazil diakritiku.
Po exporte skript prečíta prvé tri bajty výsledku a v súhrne vypíše,
či BOM naozaj sedí.

Ak sa pri niektorom súbore rozsype diakritika, nie je v UTF-8 ale
pravdepodobne vo Windows-1250 — vtedy treba prehodiť `-Encoding` pri
`Import-Csv`.

Samotný `Zluc-Csv.ps1` musí byť uložený v UTF-8 s BOM, inak PowerShell
5.1 zle prečíta diakritiku v hláseniach.

## Čo skript nerobí

- Nemaže ani nepresúva zdrojové súbory
- Nerieši duplicitné záznamy naprieč súbormi
- Súbory z priečinka `vystup` nikdy nenačítava ako vstup

## Príklad výstupu

```
Načítané súbory:
  export-a.csv                                    412 záznamov   16 stĺpcov
  export-b.csv                                    108 záznamov   16 stĺpcov
  export-c.csv                                     23 záznamov   16 stĺpcov

Kontrola štruktúry (vzor: export-a.csv):
  [v] export-b.csv
  [v] export-c.csv

Hotovo.
  Súborov:   3
  Záznamov:  543
  Stĺpcov:   16
  Kódovanie: UTF-8 (BOM: áno)
  Výsledok:  C:\prace\csv-merge-ps\vystup\merged_10092026.csv
```

## Nadväzujúci Office Script

`office-script-import-dpd.ts` importuje zásilky do hárku **Data**
v Exceli Online. Nadväzuje na zlúčený súbor dvoma spôsobmi:

- **Rozpoznáva hárok podľa predpony** — okrem `zasilky-balik` berie aj
  `merged`, teda hárok, ktorý vznikne importom `merged_DDMMYYYY.csv`
  do zošita (Excel hárok pomenuje podľa súboru)
- **Číta dátum z názvu** — ak názov obsahuje `DDMMYYYY`, použije ho ako
  dátum odoslania na zberné depo DPD. Vd’aka tomu sedí deň odoslania
  aj vtedy, keď import spustíš neskôr než prebehlo zlúčenie.
  Pri hárkoch bez dátumu v názve sa berie dnešný deň.

Duplicity kontroluje podľa DPD čísla aj Z kódu, takže opakované
spustenie nič nezdvojí. Výpis ukazuje rozpis po hárkoch:

```
Import dokončený. Pridané zásielky: 412. Preskočené duplicity: 8.
  merged_10092026: +412, duplicity 8, dátum 10.9.2026 (z názvu)
```

## Požiadavky

Windows PowerShell 5.1 alebo PowerShell 7. Skript si verziu zistí sám.

## Príbuzné

[zluc-csv-dodacie-listy](https://github.com/xks-malt1/zluc-csv-dodacie-listy)
— špecializovaná verzia pre dodacie listy, s odstraňovaním stĺpcov
a upratovaním zdrojov.
