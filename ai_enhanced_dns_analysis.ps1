<#
.SYNOPSIS
Generates an HTML report with DNS records (MX, SPF, DMARC, DKIM, and TXT) and sales opportunities for a given domain.

.PARAMETER Domain
The domain name for which the DNS records will be fetched.

.EXAMPLE
.\GenerateDnsReport.ps1 -Domain "example.com"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Domain
)

function Get-DnsRecords {
    param (
        [string]$Domain,
        [string]$RecordType
    )
    try {
        $records = Resolve-DnsName -Name $Domain -Type $RecordType
        return $records
    } catch {
        Write-Error "Failed to get $RecordType records for $Domain"
        return @()
    }
}

function Query-OpenAI {
    param (
        [string]$Prompt
    )
    $apiKey = "Your-OpenAI-API-Key"
    $apiUrl = "https://api.openai.com/v1/completions"

    $body = @{
        model = "text-davinci-003"
        prompt = $Prompt
        max_tokens = 1024
        temperature = 0.7
    } | ConvertTo-Json -Depth 10

    $headers = @{
        "Authorization" = "Bearer $apiKey"
        "Content-Type"  = "application/json"
    }

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body
        return $response.choices.text.Trim()
    } catch {
        Write-Error "Failed to query OpenAI API: $_"
        return $null
    }
}

function Generate-HtmlReport {
    param (
        [string]$Domain,
        [array]$MXRecords,
        [array]$SPFRecords,
        [array]$DMARCRecords,
        [array]$DKIMRecords,
        [array]$TXTRecords,
        [string]$Recommendations
    )

    $html = @"
<html>
<head>
    <title>DNS Report for $Domain</title>
    <style>
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid black; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <h1>DNS Report for $Domain</h1>
    <h2>MX Records</h2>
    <table>
        <tr><th>Preference</th><th>Exchange</th></tr>
"@
    foreach ($record in $MXRecords) {
        $html += "<tr><td>$($record.Preference)</td><td>$($record.Exchange)</td></tr>"
    }
    $html += "</table>"

    $html += "<h2>SPF Records</h2><table><tr><th>SPF Record</th></tr>"
    foreach ($record in $SPFRecords) {
        $html += "<tr><td>$($record.Strings)</td></tr>"
    }
    $html += "</table>"

    $html += "<h2>DMARC Records</h2><table><tr><th>DMARC Record</th></tr>"
    foreach ($record in $DMARCRecords) {
        $html += "<tr><td>$($record.Strings)</td></tr>"
    }
    $html += "</table>"

    $html += "<h2>DKIM Records</h2><table><tr><th>DKIM Record</th></tr>"
    foreach ($record in $DKIMRecords) {
        $html += "<tr><td>$($record.Strings)</td></tr>"
    }
    $html += "</table>"

    $html += "<h2>TXT Records</h2><table><tr><th>TXT Record</th></tr>"
    foreach ($record in $TXTRecords) {
        $html += "<tr><td>$($record.Strings)</td></tr>"
    }
    $html += "</table>"

    $html += "<h2>Recommendations and Insights</h2><pre>$Recommendations</pre>"

    $html += "</body></html>"

    return $html
}

# Fetch DNS records
$MXRecords = Get-DnsRecords -Domain $Domain -RecordType "MX"
$SPFRecords = Get-DnsRecords -Domain $Domain -RecordType "TXT" | Where-Object { $_.Strings -match "v=spf1" }
$DMARCRecords = Get-DnsRecords -Domain $Domain -RecordType "TXT" | Where-Object { $_.Strings -match "v=DMARC1" }
$DKIMRecords = Get-DnsRecords -Domain $Domain -RecordType "TXT" | Where-Object { $_.Strings -match "DKIM" }
$TXTRecords = Get-DnsRecords -Domain $Domain -RecordType "TXT"

# Prepare prompt for AI
$dnsData = @{
    MX = $MXRecords | ForEach-Object { @{ Preference = $_.Preference; Exchange = $_.Exchange } }
    SPF = $SPFRecords | ForEach-Object { @{ SPFRecord = $_.Strings } }
    DMARC = $DMARCRecords | ForEach-Object { @{ DMARCRecord = $_.Strings } }
    DKIM = $DKIMRecords | ForEach-Object { @{ DKIMRecord = $_.Strings } }
    TXT = $TXTRecords | ForEach-Object { @{ TXTRecord = $_.Strings } }
} | ConvertTo-Json -Depth 10

$prompt = @"
Based on the following DNS records for the domain '$Domain', provide:
1. Recommended changes to improve email security and reliability.
2. Opportunities for selling Barracuda Networks products.
3. Opportunities for selling Microsoft 365 services.
4. A narrative suitable for cold calls and prospecting.

DNS Records:
$dnsData
"@

# Query OpenAI API
Write-Output "Querying OpenAI for recommendations..."
$recommendations = Query-OpenAI -Prompt $prompt

if ($recommendations) {
    # Generate HTML report
    $htmlReport = Generate-HtmlReport -Domain $Domain -MXRecords $MXRecords -SPFRecords $SPFRecords -DMARCRecords $DMARCRecords -DKIMRecords $DKIMRecords -TXTRecords $TXTRecords -Recommendations $recommendations

    # Save the HTML report
    $reportPath = "$Domain-DnsReport.html"
    $htmlReport | Out-File -FilePath $reportPath -Encoding UTF8

    Write-Output "HTML report generated: $reportPath"
} else {
    Write-Error "Failed to retrieve recommendations from OpenAI API."
}
