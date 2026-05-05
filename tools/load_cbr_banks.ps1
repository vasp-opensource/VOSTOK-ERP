param(
    [string]$InputPath = "",
    [string]$OutputPath = "sql/import_banks_from_cbr.sql",
    [string]$Url = "https://www.cbr.ru/s/newbik"
)

$ErrorActionPreference = "Stop"

function Get-ChildByLocalName($Node, [string]$Name) {
    foreach ($Child in $Node.ChildNodes) {
        if ($Child.LocalName -eq $Name) {
            return $Child
        }
    }
    return $null
}

function Get-Attr($Node, [string]$Name) {
    if ($null -eq $Node) {
        return $null
    }
    $Value = $Node.GetAttribute($Name)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    return $Value.Trim()
}

function ConvertTo-SqlString($Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return "NULL"
    }
    return "'" + ([string]$Value).Replace("\", "\\").Replace("'", "''") + "'"
}

$TempDir = Join-Path $env:TEMP ("vostok_cbr_banks_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        $SourcePath = Join-Path $TempDir "newbik"
        Invoke-WebRequest -Uri $Url -OutFile $SourcePath -UseBasicParsing -TimeoutSec 60
    } else {
        $SourcePath = $InputPath
    }

    $Bytes = [System.IO.File]::ReadAllBytes($SourcePath)
    $XmlPath = Join-Path $TempDir "newbik.xml"

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0x50 -and $Bytes[1] -eq 0x4B) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $Zip = [System.IO.Compression.ZipFile]::OpenRead($SourcePath)
        try {
            $Entry = $Zip.Entries | Where-Object { $_.FullName.ToLower().EndsWith(".xml") } | Select-Object -First 1
            if ($null -eq $Entry) {
                throw "ZIP archive does not contain XML files"
            }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $XmlPath, $true)
        } finally {
            $Zip.Dispose()
        }
    } else {
        [System.IO.File]::WriteAllBytes($XmlPath, $Bytes)
    }

    $Xml = New-Object System.Xml.XmlDocument
    $Xml.PreserveWhitespace = $false
    $Xml.Load($XmlPath)
    $Root = $Xml.DocumentElement
    $EdDate = $Root.GetAttribute("EDDate")
    if ([string]::IsNullOrWhiteSpace($EdDate)) {
        $EdDate = $Root.GetAttribute("CreationDate")
    }

    $Columns = @(
        "BIK",
        "Bank_name",
        "Short_name",
        "Korrespond_account_number",
        "Account_status",
        "Account_type",
        "Participant_status",
        "Participant_type",
        "Services",
        "Exchange_type",
        "Region",
        "City",
        "Address",
        "Registration_number",
        "Parent_BIK",
        "Date_in",
        "Source_updated_at"
    )

    $Rows = New-Object System.Collections.Generic.List[string]
    $Entries = $Xml.SelectNodes("//*[local-name()='BICDirectoryEntry']")

    foreach ($EntryNode in $Entries) {
        $Participant = Get-ChildByLocalName $EntryNode "ParticipantInfo"
        $AccountsParent = Get-ChildByLocalName $EntryNode "Accounts"
        $Account = $null

        if ($null -ne $AccountsParent) {
            foreach ($Candidate in $AccountsParent.ChildNodes) {
                if ($Candidate.LocalName -eq "Account" -and (Get-Attr $Candidate "AccountStatus") -eq "ACAC") {
                    $Account = $Candidate
                    break
                }
            }
            if ($null -eq $Account) {
                foreach ($Candidate in $AccountsParent.ChildNodes) {
                    if ($Candidate.LocalName -eq "Account") {
                        $Account = $Candidate
                        break
                    }
                }
            }
        }

        $Bank = [ordered]@{
            BIK = Get-Attr $EntryNode "BIC"
            Bank_name = Get-Attr $Participant "NameP"
            Short_name = Get-Attr $Participant "NameP"
            Korrespond_account_number = Get-Attr $Account "Account"
            Account_status = Get-Attr $Account "AccountStatus"
            Account_type = Get-Attr $Account "RegulationAccountType"
            Participant_status = Get-Attr $Participant "ParticipantStatus"
            Participant_type = Get-Attr $Participant "PtType"
            Services = Get-Attr $Participant "Srvcs"
            Exchange_type = Get-Attr $Participant "XchType"
            Region = Get-Attr $Participant "Rgn"
            City = Get-Attr $Participant "Nnp"
            Address = Get-Attr $Participant "Adr"
            Registration_number = Get-Attr $Participant "RegN"
            Parent_BIK = Get-Attr $Participant "PrntBIC"
            Date_in = Get-Attr $Participant "DateIn"
            Source_updated_at = $EdDate
        }

        if (-not [string]::IsNullOrWhiteSpace($Bank.BIK) -and -not [string]::IsNullOrWhiteSpace($Bank.Bank_name)) {
            $Values = @()
            foreach ($Column in $Columns) {
                $Values += ConvertTo-SqlString $Bank[$Column]
            }
            $Rows.Add("    (" + ($Values -join ", ") + ")")
        }
    }

    $ColumnSql = ($Columns | ForEach-Object { "``$_``" }) -join ", "
    $UpdateSql = (($Columns | Where-Object { $_ -ne "BIK" }) | ForEach-Object { "    ``$_`` = VALUES(``$_``)" }) -join ",`n"

    $Sql = @(
        "-- Import Banks from Bank of Russia ED807 BIK directory.",
        ("-- Generated at: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")),
        ("-- ED807 date: {0}" -f $EdDate),
        "",
        "INSERT INTO ``Banks`` ($ColumnSql)",
        "VALUES",
        ($Rows -join ",`n"),
        "ON DUPLICATE KEY UPDATE",
        $UpdateSql + ";"
    ) -join "`n"

    $OutputFullPath = Resolve-Path -LiteralPath (Split-Path -Parent $OutputPath) -ErrorAction SilentlyContinue
    if ($null -eq $OutputFullPath) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
    }

    [System.IO.File]::WriteAllText((Join-Path (Get-Location) $OutputPath), $Sql + "`n", [System.Text.UTF8Encoding]::new($false))
    Write-Output "Generated $($Rows.Count) bank rows from ED807 date $EdDate into $OutputPath"
} finally {
    Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}
