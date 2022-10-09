<#
    .Synopsis
    Queries public DNS records for one or more specified domain names.

    .Description
    Queries public DNS records for one or more specified domain names.
    Results are sent to the console and if the paramater Csv is set, to a csv file.
    
    .Parameter DomainNames
    DomainNames is a mandatory parameter. DomainNames accepts multiple values as a comma-seperated list. 
    
    .Parameter ReportLocation
    If this parameter is not specified, the value for $ReportLocation will be set to "$env:USERPROFILE\Desktop\".
    
    .Parameter File
    If this paramter is not specified, the value for $File will be set to "DNS_Report-$DomainNames-$(Get-Date -Format ddMMyyyy_HHmmss).csv".
    
    .Parameter DnsIp
    If this parameter is not specified, the value for $DnsIp will be set to "8.8.8.8".
    
    .Parameter Csv
    If this parameter is specified, results are sent to the console and a csv file.
    
    .Parameter details
    If this parameter is not specified, the object's DomainName, MailExchangerDNSRecord, EmailFilter, SPFMode, and DMARCMode properties
    are displayed in the console. If this parameter is specified, all of the object's properties are displayed in the console.
    If the Csv parameter is specified, all of the object's properties are sent to the csv file.

    .Example
    Invoke-DNSQuery.ps1 -DomainNames example.org
    
    .Example
    Invoke-DNSQuery.ps1 -DomainNames example.org, example.com
    
    .Example
    Invoke-DNSQuery.ps1 -DomainNames example.org -Csv -ReportLocation C:\ -File invoke-dnsquery-results.csv

    .Example
    Invoke-DNSQuery.ps1 -DomainNames example.org -details

    .Example
    Invoke-DNSQuery.ps1 -DomainNames example.org -Csv -ReportLocation C:\ -File invoke-dnsquery-results.csv -details
#>

#MIT License

#Copyright (c) 2022 4D5A

#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.

Param(
        [parameter(Mandatory=$True)]
        [String[]]$DomainNames,
        [parameter(Mandatory=$False)]
        [String]$ReportLocation,
        [parameter(Mandatory=$False)]
        [String]$File,
        [parameter(Mandatory=$False)]
        [String]$DnsIp,
        [parameter(Mandatory=$False)]
        [Switch]$Csv,
        [parameter(Mandatory=$False)]
        [Switch]$details
    )

$ErrorActionPreference = 'SilentlyContinue'

$global:Content = $null
$global:Content = @()

If(-not($ReportLocation)){
    $ReportLocation = "$env:USERPROFILE\Desktop\"
}

If(-not($File)){
    $File = "DNS_Report-$DomainNames-$(Get-Date -Format ddMMyyyy_HHmmss).csv"
}

If(-not($DnsIp)){
    $DnsIp = "8.8.8.8"
}

$Filename = $File
$Filepath = $ReportLocation

Foreach ($DomainName in $DomainNames) {

    # Section for Obtaining the lowest preference MX record for the DomainName
    $MailExchangerDNSRecord = Resolve-DnsName -Name $DomainName -Type MX -Server $DnsIp -DnssecCd | Sort-Object -Property Preference -Descending | Select-Object -Last 1 | Select-Object -ExpandProperty NameExchange
    # Section for Identifying the Company that provides the MX service
    # Identity MX records that route incoming email to Proofpoint
    If ($MailExchangerDNSRecord -ne $null) {
        $EmailFilter = "Other"
        If ($MailExchangerDNSRecord -match "pphosted.com") {
            $EmailFilter = "Proofpoint"
        }
        # Identify MX records that route incoming email to Exchange Online
        If ($MailExchangerDNSRecord -match "mail.protection.outlook.com") {
            $EmailFilter = "Exchange Online"
        }
        # Identify MX records that route incoming email to Outlook.com
        If ($MailExchangerDNSRecord -match "olc.protection.outlook.com") {
            $EmailFilter = "Outlook.com"
        }
        # Identify MX records that route incomign email to Mimecast
        If ($MailExchangerDNSRecord -match "mimecast.com") {
            $EmailFilter = "Mimecast"
        }
        # Identify MX records that route incoming email to Sophos
        If ($MailExchangerDNSRecord -match "hydra.sophos.com") {
            $EmailFilter = "Sophos"
        }
        # Identify MX records that route incoming email to an internal email server
        If ( ($MailExchangerDNSRecord -match $DomainName) -and ($EmailFilter -ne "Exchange Online") ) {
            $EmailFilter = "Internal Email Server"
        }
        # Identify MX records that route incoming email to Barracuda Networks
        If ($MailExchangerDNSRecord -match "barracudanetworks.com") {
            $EmailFilter = "Barracuda Networks"
        }
        # Identify MX records that route incoming email to Google
        If ($MailExchangerDNSRecord -match "aspmx.l.google.com") {
            $EmailFilter = "Google"
        }
        # Identify MX records that route incoming email to GoDaddy
        If ($MailExchangerDNSRecord -match "secureserver.net") {
            $EmailFilter = "GoDaddy"
    }
}
    If ($MailExchangerDNSRecord -eq $null) {
        $MailExchangerDNSRecord = "No MX Record Found"
        $EmailFilter = "None"
    }
    # Section for Obtaining information about the Sender Policy Framework configuration in use at the DomainName
    $SPFRecordCount = (Resolve-DnsName -Name $DomainName -Type TXT -Server $DnsIp -DnssecCd | Where-Object -Property Strings -match -Value "spf1").count
    If ($SPFRecordCount -eq 0) {
        $SPFRecord = "MISCONFIGURATION: No SPF record."
    }
    If ($SPFRecordCount -gt 0) {
        If ($SPFRecordCount -gt 1) {
            $SPFRecord = "MISCONFIGURATION: Multiple SPF records."
        }
        If ($SPFRecordCount -eq 1) {
            $SPFRecord = Resolve-DnsName -Name $DomainName -Type TXT -Server $DnsIp -DnssecCd | Where-Object -Property Strings -match -Value "spf1" | Select-Object -ExpandProperty Strings
            If ($SPFRecord -match '~all') {
                $SPFMode = "SoftFail mode"
            }
            If ($SPFRecord -match '-all') {
                $SPFMode = "HardFail mode"
            }
        }
    }
    #Section for Obtaining information about the Domain-Based Message Authentication, Reporting & Conformance configuration in use at the DomainName
    $DMARCRecordCount = (Resolve-DnsName -Name _dmarc.$DomainName -Type TXT -Server $DnsIp -DnssecCd | Where-Object -Property Name -match -Value "_dmarc.$DomainName").count
    If ($DMARCRecordCount -eq 0) {
        $DMARCRecord = "MISCONFIGURATION: No DMARC record."
    }
    If ($DMARCRecordCount -gt 0) {
        If ($DMARCRecordCount -gt 1) {
            $DMARCRecord = "MISCONFIGURATION: Multiple DMARC records."
        }
        If ($DMARCRecordCount -eq 1) {
            $DMARCRecord = Resolve-DnsName -Name _dmarc.$DomainName -Type TXT -Server $DnsIp -DnssecCd | Where-Object -Property Strings -match -Value "DMARC1" | Select-Object -ExpandProperty Strings
            If ($DMARCRecord -eq $null) {
                $DMARCRecord = "MISCONFIGURATION: There is an invalid DMARC record."
            }
            If ($DMARCRecord -match 'p=quarantine') {
                $DMARCMode = "Quarantine mode"
            }
            If ($DMARCRecord -match 'p=reject') {
                $DMARCMode = "Reject mode"
            }
            If ($DMARCRecord -match 'p=none') {
                $DMARCMode = "Reporting only mode"
            }
        }
    }
    $global:Content += [pscustomobject]@{DomainName = $DomainName; MailExchangerDNSRecord = $MailExchangerDNSRecord; EmailFilter = $EmailFilter; SPFRecord = $SPFRecord; SPFMode = $SPFMode; DMARCRecord = $DMARCRecord; DMARCMode = $DMARCMode}

}

If ($Csv) {
    $global:Content | Export-Csv -Path "$FilePath\$Filename" -Append -Encoding Ascii -NoTypeInformation
}

If ($Details) {
    $global:Content | Format-Table
}
Else {
    $global:Content | Select-Object DomainName, MailExchangerDNSRecord, EmailFilter, SPFMode, DMARCMode | Format-Table
}