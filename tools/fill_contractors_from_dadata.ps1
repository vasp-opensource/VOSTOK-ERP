param(
    [string]$MysqlPath = $(if ($env:VOSTOK_MYSQL_PATH) { $env:VOSTOK_MYSQL_PATH } else { "mysql" }),
    [string]$DbHost = $env:VOSTOK_DB_HOST,
    [int]$DbPort = $(if ($env:VOSTOK_DB_PORT) { [int]$env:VOSTOK_DB_PORT } else { 3306 }),
    [string]$DbName = $env:VOSTOK_DB_NAME,
    [string]$DbUser = $env:VOSTOK_DB_USER,
    [string]$DbPassword = $env:VOSTOK_DB_PASSWORD,
    [string]$DaDataToken = $env:DADATA_TOKEN,
    [string]$DaDataSecret = $env:DADATA_SECRET,
    [int]$Limit = 100,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$DaDataUrl = "https://suggestions.dadata.ru/suggestions/api/4_1/rs/findById/party"

if ([string]::IsNullOrWhiteSpace($DbHost)) { throw "Set VOSTOK_DB_HOST or pass -DbHost" }
if ([string]::IsNullOrWhiteSpace($DbName)) { throw "Set VOSTOK_DB_NAME or pass -DbName" }
if ([string]::IsNullOrWhiteSpace($DbUser)) { throw "Set VOSTOK_DB_USER or pass -DbUser" }
if ([string]::IsNullOrWhiteSpace($DaDataToken)) { throw "Set DADATA_TOKEN or pass -DaDataToken" }

function Resolve-MysqlPath([string]$PathValue) {
    if (-not [string]::IsNullOrWhiteSpace($PathValue) -and $PathValue -ne "mysql") {
        if (Test-Path -LiteralPath $PathValue) {
            return (Resolve-Path -LiteralPath $PathValue).Path
        }
        throw "mysql.exe not found at '$PathValue'. Set VOSTOK_MYSQL_PATH to the full mysql.exe path."
    }

    $Command = Get-Command "mysql.exe" -ErrorAction SilentlyContinue
    if ($null -ne $Command) {
        return $Command.Source
    }

    $Candidates = @(
        "C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe",
        "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe",
        "C:\Program Files (x86)\MySQL\MySQL Server 8.0\bin\mysql.exe",
        "C:\xampp\mysql\bin\mysql.exe",
        "C:\laragon\bin\mysql\mysql-8.0\bin\mysql.exe"
    )

    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate) {
            return $Candidate
        }
    }

    throw "mysql.exe not found. Install MySQL client or set VOSTOK_MYSQL_PATH to the full mysql.exe path."
}

$MysqlPath = Resolve-MysqlPath $MysqlPath

function ConvertTo-SqlString($Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return "NULL"
    }
    return "'" + ([string]$Value).Replace("\", "\\").Replace("'", "''") + "'"
}

function ConvertFrom-DaDataDate($Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }
    try {
        $Milliseconds = [int64]$Value
        return ([DateTimeOffset]::FromUnixTimeMilliseconds($Milliseconds)).UtcDateTime.ToString("yyyy-MM-dd")
    } catch {
        return $null
    }
}

function ConvertFrom-DaDataStatus($Value) {
    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }
    return [string]$Value
}

function Invoke-MySql([string]$Sql) {
    $Arguments = @(
        "--batch",
        "--raw",
        "--skip-column-names",
        "--default-character-set=utf8mb4",
        "--host=$DbHost",
        "--port=$DbPort",
        "--user=$DbUser",
        $DbName
    )

    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo.FileName = $MysqlPath
    $Process.StartInfo.Arguments = ($Arguments | ForEach-Object {
        if ($_ -match "\s") { '"' + $_.Replace('"', '\"') + '"' } else { $_ }
    }) -join " "
    $Process.StartInfo.RedirectStandardInput = $true
    $Process.StartInfo.RedirectStandardOutput = $true
    $Process.StartInfo.RedirectStandardError = $true
    $Process.StartInfo.UseShellExecute = $false
    $Process.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $Process.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    if (-not [string]::IsNullOrWhiteSpace($DbPassword)) {
        $Process.StartInfo.EnvironmentVariables["MYSQL_PWD"] = $DbPassword
    } elseif (-not [string]::IsNullOrWhiteSpace($env:MYSQL_PWD)) {
        $Process.StartInfo.EnvironmentVariables["MYSQL_PWD"] = $env:MYSQL_PWD
    }

    [void]$Process.Start()
    $Process.StandardInput.WriteLine($Sql)
    $Process.StandardInput.Close()
    $Output = $Process.StandardOutput.ReadToEnd()
    $ErrorText = $Process.StandardError.ReadToEnd()
    $Process.WaitForExit()

    if ($Process.ExitCode -ne 0) {
        throw "mysql exit code $($Process.ExitCode): $ErrorText"
    }
    return $Output
}

function Find-DaDataParty([string]$Inn, [string]$Kpp) {
    $Headers = @{
        "Authorization" = "Token $DaDataToken"
        "Content-Type" = "application/json; charset=utf-8"
        "Accept" = "application/json"
    }
    if (-not [string]::IsNullOrWhiteSpace($DaDataSecret)) {
        $Headers["X-Secret"] = $DaDataSecret
    }

    $Body = @{ query = $Inn }
    if (-not [string]::IsNullOrWhiteSpace($Kpp)) {
        $Body["kpp"] = $Kpp
    }

    $JsonBody = $Body | ConvertTo-Json -Depth 5
    $Response = Invoke-RestMethod -Method Post -Uri $DaDataUrl -Headers $Headers -Body $JsonBody
    if ($null -eq $Response.suggestions -or $Response.suggestions.Count -eq 0) {
        return $null
    }

    if (-not [string]::IsNullOrWhiteSpace($Kpp)) {
        foreach ($Suggestion in $Response.suggestions) {
            if ($Suggestion.data.kpp -eq $Kpp) {
                return $Suggestion
            }
        }
    }
    return $Response.suggestions[0]
}

$SelectSql = @"
SELECT
    `id`,
    COALESCE(`INN`, ''),
    COALESCE(`KPP`, '')
FROM `Contractors`
WHERE `INN` IS NOT NULL
  AND TRIM(`INN`) <> ''
  AND (
        `Short_name` IS NULL OR TRIM(`Short_name`) = ''
     OR TRIM(`Short_name`) = TRIM(`INN`)
     OR `Full_name` IS NULL OR TRIM(`Full_name`) = ''
     OR `KPP` IS NULL OR TRIM(`KPP`) = ''
     OR `OGRN` IS NULL OR TRIM(`OGRN`) = ''
     OR `Director` IS NULL OR TRIM(`Director`) = ''
     OR `Post_address` IS NULL OR TRIM(`Post_address`) = ''
     OR `Status` IS NULL OR TRIM(`Status`) = ''
  )
ORDER BY `id`
LIMIT $Limit;
"@

$Rows = Invoke-MySql $SelectSql
if ([string]::IsNullOrWhiteSpace($Rows)) {
    Write-Output "No Contractors rows require DaData enrichment."
    exit 0
}

$Updated = 0
$NotFound = 0

foreach ($Line in ($Rows -split "`r?`n")) {
    if ([string]::IsNullOrWhiteSpace($Line)) {
        continue
    }

    $Parts = $Line -split "`t"
    $Id = [int]$Parts[0]
    $Inn = $Parts[1]
    $Kpp = if ($Parts.Count -gt 2) { $Parts[2] } else { "" }

    $Suggestion = Find-DaDataParty $Inn $Kpp
    if ($null -eq $Suggestion) {
        Write-Output "Contractor id=$Id INN=${Inn}: not found in DaData"
        $NotFound++
        continue
    }

    $Data = $Suggestion.data
    $ShortName = $Data.name.short_with_opf
    if ([string]::IsNullOrWhiteSpace($ShortName)) { $ShortName = $Suggestion.value }
    $FullName = $Data.name.full_with_opf
    if ([string]::IsNullOrWhiteSpace($FullName)) { $FullName = $ShortName }
    $Address = $Data.address.unrestricted_value
    $Status = ConvertFrom-DaDataStatus $Data.state.status
    $RegistrationDate = ConvertFrom-DaDataDate $Data.state.registration_date
    $LiquidationDate = ConvertFrom-DaDataDate $Data.state.liquidation_date
    $Director = $Data.management.name

    $UpdateSql = @"
UPDATE `Contractors`
SET
    `Short_name` = CASE WHEN `Short_name` IS NULL OR TRIM(`Short_name`) = '' OR TRIM(`Short_name`) = TRIM(`INN`) THEN $(ConvertTo-SqlString $ShortName) ELSE `Short_name` END,
    `Full_name` = CASE WHEN `Full_name` IS NULL OR TRIM(`Full_name`) = '' THEN $(ConvertTo-SqlString $FullName) ELSE `Full_name` END,
    `KPP` = CASE WHEN `KPP` IS NULL OR TRIM(`KPP`) = '' THEN $(ConvertTo-SqlString $Data.kpp) ELSE `KPP` END,
    `OGRN` = CASE WHEN `OGRN` IS NULL OR TRIM(`OGRN`) = '' THEN $(ConvertTo-SqlString $Data.ogrn) ELSE `OGRN` END,
    `Director` = CASE WHEN `Director` IS NULL OR TRIM(`Director`) = '' THEN $(ConvertTo-SqlString $Director) ELSE `Director` END,
    `Post_address` = CASE WHEN `Post_address` IS NULL OR TRIM(`Post_address`) = '' THEN $(ConvertTo-SqlString $Address) ELSE `Post_address` END,
    `Status` = CASE WHEN `Status` IS NULL OR TRIM(`Status`) = '' THEN $(ConvertTo-SqlString $Status) ELSE `Status` END,
    `Registration_date` = CASE WHEN `Registration_date` IS NULL THEN $(ConvertTo-SqlString $RegistrationDate) ELSE `Registration_date` END,
    `Liquidation_date` = CASE WHEN `Liquidation_date` IS NULL THEN $(ConvertTo-SqlString $LiquidationDate) ELSE `Liquidation_date` END,
    `Source_name` = 'dadata',
    `Source_updated_at` = NOW(),
    `updated_at` = NOW()
WHERE `id` = $Id;
"@

    if ($DryRun) {
        Write-Output "-- Contractor id=$Id INN=$Inn"
        Write-Output $UpdateSql
    } else {
        Invoke-MySql $UpdateSql | Out-Null
        Write-Output "Contractor id=$Id INN=${Inn}: updated from DaData"
    }
    $Updated++
}

Write-Output "Done. Updated=$Updated NotFound=$NotFound DryRun=$DryRun"
