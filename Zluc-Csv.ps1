# =====================================================================
#  Všeobecné zlúčenie CSV súborov
#
#  Zlúči všetky CSV z priečinka od najväčšieho po najmenší (podľa počtu
#  záznamov) do súboru merged_DDMMYYYY.csv.
#
#  Pred zlúčením overí, že všetky súbory majú rovnakú dátovú štruktúru
#  — rovnaké názvy stĺpcov v rovnakom poradí. Ak nie, nič nezapíše.
#
#  Kódovanie: vstupy sa kontrolujú na UTF-8 BOM, výstup ho má vždy.
# =====================================================================

# ------------------------- NASTAVENIA --------------------------------
#  Predvolene sa berie priečinok, v ktorom leží skript. Ak potrebuješ
#  iný, prepíš cesty natvrdo (napr. "C:\data").
$Korenovy  = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

$Zdroj     = $Korenovy                           # priečinok so vstupnými CSV
$Vystup    = Join-Path $Korenovy "vystup"        # kam sa uloží výsledok
$Oddelovac = ";"
$Maska     = "*.csv"                             # napr. "zasilky-balik*.csv"

# $true = poradie stĺpcov musí sedieť, nielen ich zoznam
$PrisnePoradie = $true

# Voliteľne: stĺpce na odstránenie z výsledku. Prázdne = ponechať všetky.
# Podporuje zástupné znaky, napr. "Pozn*"
$Odstranit = @()
# ---------------------------------------------------------------------

$JeP7 = $PSVersionTable.PSVersion.Major -ge 7


# --- pomocné funkcie -------------------------------------------------

#  Odstráni BOM a orezáva medzery z názvu stĺpca.
function Ocisti([string]$text) {
    if ($null -eq $text) { return "" }
    ($text -replace "^\uFEFF", "").Trim()
}

#  Normalizuje názov stĺpca na porovnávanie — ignoruje diakritiku,
#  veľkosť písmen a viacnásobné medzery.
function Normalizuj([string]$text) {
    $t = Ocisti $text
    if ([string]::IsNullOrWhiteSpace($t)) { return "" }

    $t = ($t -replace '\s+', ' ').Normalize([Text.NormalizationForm]::FormD)

    $sb = [Text.StringBuilder]::new()
    foreach ($z in $t.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($z) -ne 'NonSpacingMark') {
            [void]$sb.Append($z)
        }
    }
    return $sb.ToString().ToLowerInvariant()
}

#  Zistí, či súbor začína UTF-8 BOM (EF BB BF).
function MaBom([string]$cesta) {
    if (-not (Test-Path $cesta)) { return $false }

    $bajty = if ($JeP7) {
        [byte[]](Get-Content $cesta -AsByteStream -TotalCount 3)
    } else {
        [byte[]](Get-Content $cesta -Encoding Byte -TotalCount 3)
    }

    return ($bajty.Count -ge 3 -and $bajty[0] -eq 0xEF -and $bajty[1] -eq 0xBB -and $bajty[2] -eq 0xBF)
}


# --- príprava --------------------------------------------------------

if (-not (Test-Path $Vystup)) {
    New-Item -ItemType Directory -Path $Vystup | Out-Null
}

$vystupPlny = [System.IO.Path]::GetFullPath($Vystup)

#  Súbory z výstupného priečinka sa nikdy nenačítavajú ako vstup.
$subory = @(
    Get-ChildItem -Path $Zdroj -Filter $Maska -File |
    Where-Object { [System.IO.Path]::GetDirectoryName($_.FullName) -ne $vystupPlny }
)

if ($subory.Count -eq 0) {
    Write-Warning "V priečinku $Zdroj nie sú žiadne súbory podľa masky '$Maska'."
    return
}


# --- načítanie -------------------------------------------------------

$nacitane = foreach ($s in $subory) {

    if (-not (MaBom $s.FullName)) {
        Write-Warning "Súbor '$($s.Name)' nemá UTF-8 BOM — over diakritiku vo výstupe."
    }

    $data = @(Import-Csv -Path $s.FullName -Delimiter $Oddelovac -Encoding UTF8)

    if ($data.Count -eq 0) {
        Write-Warning "Súbor '$($s.Name)' je prázdny — preskakujem."
        continue
    }

    [PSCustomObject]@{
        Nazov    = $s.Name
        Pocet    = $data.Count
        Hlavicky = @($data[0].PSObject.Properties.Name | ForEach-Object { Ocisti $_ })
        Data     = $data
    }
}

$nacitane = @($nacitane)

if ($nacitane.Count -eq 0) {
    Write-Warning "Žiadny použiteľný súbor."
    return
}

$zoradene = @($nacitane | Sort-Object Pocet -Descending)

Write-Host "`nNačítané súbory:" -ForegroundColor Cyan
foreach ($n in $zoradene) {
    Write-Host ("  {0,-45} {1,7} záznamov   {2} stĺpcov" -f $n.Nazov, $n.Pocet, $n.Hlavicky.Count)
}


# --- kontrola dátovej štruktúry --------------------------------------
#  Vzorom je najväčší súbor, ostatné sa porovnávajú proti nemu.

$vzor    = $zoradene[0]
$problem = $false

if ($zoradene.Count -eq 1) {
    Write-Host "`n  (jediný súbor — kontrola štruktúry nie je potrebná)" -ForegroundColor DarkGray
} else {
    Write-Host "`nKontrola štruktúry (vzor: $($vzor.Nazov)):" -ForegroundColor Cyan

    $vzorNorm = @($vzor.Hlavicky | ForEach-Object { Normalizuj $_ })

    foreach ($n in $zoradene) {
        if ($n.Nazov -eq $vzor.Nazov) { continue }

        $norm  = @($n.Hlavicky | ForEach-Object { Normalizuj $_ })
        $chyby = @()

        $navyse = @()
        for ($i = 0; $i -lt $norm.Count; $i++) {
            if ($vzorNorm -notcontains $norm[$i]) { $navyse += $n.Hlavicky[$i] }
        }

        $chybne = @()
        for ($i = 0; $i -lt $vzorNorm.Count; $i++) {
            if ($norm -notcontains $vzorNorm[$i]) { $chybne += $vzor.Hlavicky[$i] }
        }

        if ($chybne.Count -gt 0) { $chyby += "chýba: "  + ($chybne -join ", ") }
        if ($navyse.Count -gt 0) { $chyby += "navyše: " + ($navyse -join ", ") }

        if ($chyby.Count -eq 0 -and $PrisnePoradie) {
            for ($i = 0; $i -lt $vzorNorm.Count; $i++) {
                if ($vzorNorm[$i] -ne $norm[$i]) {
                    $chyby += ("iné poradie na pozícii {0}: '{1}' namiesto '{2}'" -f `
                        ($i + 1), $n.Hlavicky[$i], $vzor.Hlavicky[$i])
                    break
                }
            }
        }

        if ($chyby.Count -gt 0) {
            Write-Host ("  [x] {0}" -f $n.Nazov) -ForegroundColor Red
            foreach ($c in $chyby) { Write-Host ("      {0}" -f $c) -ForegroundColor Red }
            $problem = $true
        } else {
            Write-Host ("  [v] {0}" -f $n.Nazov) -ForegroundColor DarkGray
        }
    }
}

if ($problem) {
    Write-Host ""
    Write-Warning "Súbory nemajú rovnakú dátovú štruktúru. Nič sa nezlúčilo."
    return
}


# --- voliteľné odstránenie stĺpcov -----------------------------------

$hlavicky = $vzor.Hlavicky

if ($Odstranit.Count -gt 0) {
    $normOdstranit = @($Odstranit | ForEach-Object { Normalizuj $_ })
    $najdene = @{}

    $hlavicky = @($vzor.Hlavicky | Where-Object {
        $nm    = Normalizuj $_
        $zhoda = @($normOdstranit | Where-Object { $nm -like $_ })
        if ($zhoda.Count -gt 0) { $najdene[$zhoda[0]] = $_ }
        $zhoda.Count -eq 0
    })

    Write-Host "`nStĺpce:" -ForegroundColor Cyan
    foreach ($o in $Odstranit) {
        $nm = Normalizuj $o
        if ($najdene.ContainsKey($nm)) {
            Write-Host ("  odstránené: {0}" -f $najdene[$nm]) -ForegroundColor DarkGray
        } else {
            Write-Warning "Stĺpec '$o' sa nenašiel."
        }
    }

    if ($hlavicky.Count -eq 0) {
        Write-Warning "Po odstránení neostal žiadny stĺpec. Skontroluj `$Odstranit."
        return
    }
}


# --- zlúčenie --------------------------------------------------------
#  Poradie: od najväčšieho súboru po najmenší.

$zlucene = foreach ($n in $zoradene) {
    $n.Data | Select-Object $hlavicky
}


# --- export ----------------------------------------------------------
#  Zápis cez .NET s vynúteným UTF-8 BOM — rovnaký výsledok v 5.1 aj 7.

$nazovVystupu = "merged_{0}.csv" -f (Get-Date -Format "ddMMyyyy")
$cielovaCesta = [System.IO.Path]::GetFullPath((Join-Path $Vystup $nazovVystupu))

if (Test-Path $cielovaCesta) {
    Write-Warning "Súbor $nazovVystupu už existuje a bude prepísaný."
}

$riadky = if ($JeP7) {
    $zlucene | ConvertTo-Csv -Delimiter $Oddelovac -NoTypeInformation -UseQuotes AsNeeded
} else {
    $zlucene | ConvertTo-Csv -Delimiter $Oddelovac -NoTypeInformation
}

[System.IO.File]::WriteAllLines($cielovaCesta, $riadky, [System.Text.UTF8Encoding]::new($true))

$maBom = MaBom $cielovaCesta

if (-not $maBom) {
    Write-Warning "Výstup nemá BOM — Excel môže pokaziť diakritiku."
}

Write-Host "`nHotovo." -ForegroundColor Green
Write-Host ("  Súborov:   {0}" -f $zoradene.Count)
Write-Host ("  Záznamov:  {0}" -f @($zlucene).Count)
Write-Host ("  Stĺpcov:   {0}" -f $hlavicky.Count)
Write-Host ("  Kódovanie: UTF-8 (BOM: {0})" -f $(if ($maBom) { "áno" } else { "nie" }))
Write-Host ("  Výsledok:  {0}" -f $cielovaCesta)
