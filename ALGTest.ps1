# Function to check if the script is running as Administrator
function Test-IsAdmin {
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to check if a firewall rule exists for outbound UDP 5060
function Test-FirewallRule {
    $firewallRule = Get-NetFirewallRule -Direction Outbound -Action Allow -Enabled True |
        Get-NetFirewallPortFilter | Where-Object { $_.Protocol -eq 'UDP' -and $_.LocalPort -eq '5060' }

    if ($firewallRule) {
        Write-Host "✅ Firewall check: An outbound rule for UDP 5060 exists." -ForegroundColor Green
    } else {
        Write-Host "⚠ WARNING: No firewall rule allowing outbound UDP 5060 was found!" -ForegroundColor Yellow
        Write-Host "   The test may fail if the firewall blocks traffic." -ForegroundColor Yellow
    }
}

# Admin check
if (Test-IsAdmin) {
    Write-Host "Running as Administrator. Checking firewall rules..." -ForegroundColor Cyan
    Test-FirewallRule
} else {
    Write-Host "WARNING: This script is NOT running as Administrator!" -ForegroundColor Yellow
    Write-Host "Firewall rules cannot be checked without Admin privileges." -ForegroundColor Yellow
    Write-Host "If you want the firewall check, re-run this script as Administrator." -ForegroundColor Yellow
}

# Prompt the user for the SIP server (IP address or hostname)
$SIPServer = Read-Host "Enter the SIP server (IP address or hostname)"
$SIPPort = 5060  # Default SIP UDP port

# Validate and resolve the SIP server
if ([System.Net.IPAddress]::TryParse($SIPServer, [ref]$null)) {
    $RemoteIPAddress = [System.Net.IPAddress]::Parse($SIPServer)
} else {
    try {
        Write-Host "Resolving DNS for $SIPServer..." -ForegroundColor Cyan
        $ResolvedIP = Resolve-DnsName -Name $SIPServer -ErrorAction Stop | Select-Object -First 1 -ExpandProperty IPAddress
        $RemoteIPAddress = [System.Net.IPAddress]::Parse($ResolvedIP)
        Write-Host "Resolved $SIPServer to IP: $RemoteIPAddress" -ForegroundColor Green
    } catch {
        Write-Host "Failed to resolve DNS name for $SIPServer. Please check the hostname and try again." -ForegroundColor Red
        exit
    }
}

# Define the SIP request
$SIPRequest = @"
OPTIONS sip:$SIPServer SIP/2.0
Via: SIP/2.0/UDP 192.0.2.1:5060;branch=z9hG4bK-524287-1---e81234abcd;rport
Max-Forwards: 70
To: <sip:$SIPServer>
From: <sip:test@$SIPServer>;tag=abcd1234
Call-ID: 12345678@$SIPServer
CSeq: 1 OPTIONS
Content-Length: 0

"@

# Create a UDP client
$UDPClient = New-Object System.Net.Sockets.UdpClient

try {
    # Send the SIP request
    $RemoteEndPoint = New-Object System.Net.IPEndPoint $RemoteIPAddress, $SIPPort
    $RequestBytes = [System.Text.Encoding]::ASCII.GetBytes($SIPRequest)
    
    Write-Host ("Sending SIP request to {0}:{1}..." -f $RemoteIPAddress, $SIPPort) -ForegroundColor Cyan
    $UDPClient.Send($RequestBytes, $RequestBytes.Length, $RemoteEndPoint)

    # Wait for a response
    $ResponseEndPoint = $null
    $Timeout = 5000  # 5 seconds timeout
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($Stopwatch.ElapsedMilliseconds -lt $Timeout -and $UDPClient.Available -eq 0) {
        Start-Sleep -Milliseconds 100
    }
    $Stopwatch.Stop()

    if ($UDPClient.Available -gt 0) {
        $ResponseBytes = $UDPClient.Receive([ref]$ResponseEndPoint)
        $ResponseMessage = [System.Text.Encoding]::ASCII.GetString($ResponseBytes)
        
        Write-Host "Response received from ${SIPServer}:" -ForegroundColor Green
        Write-Host $ResponseMessage

        # Analyze the response for SIP ALG detection
        if ($ResponseMessage -match "Via: SIP/2.0/UDP .*;rport=.*;branch=") {
            Write-Host "🚨 SIP ALG is likely ENABLED on the gateway. The 'Via' header has been modified." -ForegroundColor Red
        } else {
            Write-Host "✅ SIP ALG is likely DISABLED. The 'Via' header appears intact." -ForegroundColor Green
        }
    } else {
        Write-Host "⚠ No response received from the server. SIP ALG may not be interfering, the address entered is incorrect, or the server did not respond." -ForegroundColor Yellow
    }
} catch {
    Write-Host "An error occurred: $_" -ForegroundColor Red
} finally {
    # Close the UDP client
    $UDPClient.Close()
}
