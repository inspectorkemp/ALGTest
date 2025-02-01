
# Prompt the user for the SIP server (IP address or hostname)
$SIPServer = Read-Host "Enter the SIP server (IP address or hostname)"
$SIPPort = 5060  # Default SIP UDP port

# Validate and resolve the SIP server
if ([System.Net.IPAddress]::TryParse($SIPServer, [ref]$null)) {
    $RemoteIPAddress = [System.Net.IPAddress]::Parse($SIPServer)
} else {
    try {
        $ResolvedIP = Resolve-DnsName -Name $SIPServer -ErrorAction Stop | Select-Object -First 1 -ExpandProperty IPAddress
        $RemoteIPAddress = [System.Net.IPAddress]::Parse($ResolvedIP)
    } catch {
        Write-Host "❌ Failed to resolve DNS name for $SIPServer. Please check the hostname and try again." -ForegroundColor Red
        exit
    }
}

# Define the SIP request
$SIPRequest = @"
OPTIONS sip:example.com SIP/2.0
Via: SIP/2.0/UDP 192.0.2.1:5060;branch=z9hG4bK-524287-1---e81234abcd
Max-Forwards: 70
To: <sip:example.com>
From: <sip:test@example.com>;tag=abcd1234
Call-ID: 12345678@192.0.2.1
CSeq: 1 OPTIONS
Content-Length: 0

"@ -replace "`n", "`r`n"  # Ensure correct SIP formatting with CRLF

# Create a UDP client
$UDPClient = New-Object System.Net.Sockets.UdpClient

try {
    # Send the SIP request
    $RemoteEndPoint = New-Object System.Net.IPEndPoint $RemoteIPAddress, $SIPPort
    $RequestBytes = [System.Text.Encoding]::ASCII.GetBytes($SIPRequest)
    $UDPClient.Send($RequestBytes, $RequestBytes.Length, $RemoteEndPoint)

    Write-Host ("✅ SIP request sent to {0}:{1}" -f $RemoteIPAddress, $SIPPort) -ForegroundColor Green

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
        Write-Host "✅ Response received:" -ForegroundColor Green
        Write-Host $ResponseMessage

        # Analyze the response
        if ($ResponseMessage -match "Via: SIP/2.0/UDP .*;rport=.*;branch=") {
            Write-Host "🚨 SIP ALG is likely ENABLED on the gateway. The 'Via' header has been modified." -ForegroundColor Red
        } else {
            Write-Host "✅ SIP ALG is likely DISABLED. The 'Via' header appears intact." -ForegroundColor Green
        }
    } else {
        Write-Host "⚠ No response received from the server. SIP ALG may not be interfering, or the server did not respond." -ForegroundColor Yellow -BackgroundColor Green
    }
} catch {
    Write-Host "❌ An error occurred: $_" -ForegroundColor Red
} finally {
    # Close the UDP client
    $UDPClient.Close()
}
