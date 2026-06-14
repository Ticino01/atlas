# Patch-Anleitung: lib-search.ps1 für Obsidian und Notion

Damit `@obsidian` und `@notion` als Filter funktionieren UND die Treffer
beim Enter wirklich richtig geöffnet werden, brauchst du zwei kleine
Anpassungen in `lib-search.ps1`.

Suche die folgenden Stellen mit `Strg + F` und tausche sie aus.

---

## Patch 1 — `Parse-AtlasQuery`: neue Type-Filter erkennen

Such in `lib-search.ps1` nach der Funktion `Parse-AtlasQuery`. Sie hat
wahrscheinlich eine Liste der erlaubten Typen oder ein Switch. Suche
nach einer Zeile die ungefähr so aussieht:

```powershell
$validTypes = @('file', 'web', 'bookmark', 'recent')
```

oder

```powershell
if ($type -in @('file', 'web', 'bookmark', 'recent')) {
```

**Ersetzen mit:**

```powershell
$validTypes = @('file', 'web', 'bookmark', 'recent', 'obsidian', 'notion', 'note')
```

Hinweis: `note` als Alias akzeptieren ist Komfort — du kannst `@note`
tippen und es matcht sowohl Obsidian- als auch Notion-Einträge. Falls du
das nicht willst, lass `note` weg.

### Falls du `note` als Alias willst

Such die Stelle wo der Type aus dem Query gezogen wird und ergänz
direkt danach:

```powershell
# Alias: @note matcht obsidian UND notion
if ($type -eq 'note') {
    $type = @('obsidian', 'notion')
}
```

Die `Search-AtlasIndex`-Funktion muss dann auch Listen von Typen
akzeptieren — falls sie nur einen einzelnen String erwartet, lass diese
Alias-Logik weg und tippe einfach `@obsidian` oder `@notion` direkt.

---

## Patch 2 — `Invoke-AtlasAction`: neue Typen behandeln

Such die Funktion `Invoke-AtlasAction`. Sie hat wahrscheinlich einen
`switch`-Block über `$Record.type`. Sieht ungefähr so aus:

```powershell
function Invoke-AtlasAction {
    param($Record)

    switch ($Record.type) {
        'file'     { Start-Process $Record.action_data }
        'web'      { Start-Process $Record.action_data }
        'bookmark' { Start-Process $Record.action_data }
        'recent'   { Start-Process $Record.action_data }
        default    { Start-Process $Record.action_data }
    }

    # Pick aufzeichnen
    Add-AtlasPick -RecordId $Record.id
}
```

**Ergänzen mit den zwei neuen Cases** (vor dem `default`-Block):

```powershell
'obsidian' {
    # Obsidian-URI-Scheme: oeffnet die Notiz direkt in Obsidian
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

    $vaultBase = "C:\Users\aehsani\OneDrive - bossinfo.ch AG\Dokumente\Obsidian\Abbas"
    $vaultName = "Abbas"

    $filePath = $Record.action_data
    $relativePath = $filePath.Substring($vaultBase.Length).TrimStart('\')
    $relativePath = $relativePath -replace '\.md$', ''
    $relativePath = $relativePath -replace '\\', '/'

    $encodedVault = [System.Web.HttpUtility]::UrlEncode($vaultName)
    $encodedFile = [System.Web.HttpUtility]::UrlEncode($relativePath)
    $uri = "obsidian://open?vault=$encodedVault&file=$encodedFile"

    Write-AtlasLog -Component 'action' -Level INFO -Message "Opening Obsidian note: $relativePath"
    Start-Process $uri
}
'notion' {
    # Notion-Page: oeffnet die Page-URL im Browser
    Write-AtlasLog -Component 'action' -Level INFO -Message "Opening Notion page: $($Record.action_data)"
    Start-Process $Record.action_data
}
```

### Wichtig zum Vault-Pfad

Der Pfad `C:\Users\aehsani\OneDrive - bossinfo.ch AG\Dokumente\Obsidian\Abbas`
ist hardcoded. **Sauberer wäre**, ihn aus der Config zu lesen — also:

In `config.ps1` ergänzen:

```powershell
$Config.ObsidianVault = "C:\Users\aehsani\OneDrive - bossinfo.ch AG\Dokumente\Obsidian\Abbas"
$Config.ObsidianVaultName = "Abbas"
```

Dann in `Invoke-AtlasAction`:

```powershell
$vaultBase = $Config.ObsidianVault
$vaultName = $Config.ObsidianVaultName
```

Das ist sauberer und bei einer späteren Vault-Verschiebung musst du nur
die Config anfassen.

---

## Test nach den Patches

1. **Speichern** und PowerShell neu starten (oder Skript erneut
   sourcen).

2. **Indexer laufen lassen:**
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File ".\index-obsidian.ps1"
   ```

3. **Atlas öffnen** (Hotkey oder direkt) und tippen:
   ```
   @obsidian
   ```
   Du solltest jetzt nur Obsidian-Notizen sehen.

4. **Eine Notiz auswählen + Enter** → Obsidian sollte sich öffnen und
   genau auf diese Notiz springen.

---

## Falls Obsidian sich nicht öffnet

Möglicher Grund: Das `obsidian://`-URI-Scheme ist nicht registriert.
Test in PowerShell:

```powershell
Start-Process "obsidian://open?vault=Abbas"
```

Wenn das nichts macht: Obsidian einmal manuell starten. Beim ersten
Start registriert Obsidian das URI-Scheme im System.

Falls es danach immer noch nicht klappt: Manuell registrieren über
Obsidian-Settings → Community Plugins → Obsidian-URI ist in neueren
Versionen Standard.
