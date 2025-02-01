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

# Specify the external SIP server and port
$SIPServer = "192.168.1.1"  # Replace with an actual SIP server IP or domain
$SIPPort = 5060

# Check if the SIP server is an IP address or needs DNS resolution
if ([System.Net.IPAddress]::TryParse($SIPServer, [ref]$null)) {
    $RemoteIPAddress = [System.Net.IPAddress]::Parse($SIPServer)
} else {
    try {
        $RemoteIPAddress = [System.Net.IPAddress]::Parse((Resolve-DnsName -Name $SIPServer | Select-Object -First 1).IPAddress)
    } catch {
        Write-Host "Failed to resolve DNS name for $SIPServer" -ForegroundColor Red
        return
    }
}

# Create a UDP client
$UDPClient = New-Object System.Net.Sockets.UdpClient

try {
    # Send the SIP request
    $RemoteEndPoint = New-Object System.Net.IPEndPoint $RemoteIPAddress, $SIPPort
    $RequestBytes = [System.Text.Encoding]::ASCII.GetBytes($SIPRequest)
    $UDPClient.Send($RequestBytes, $RequestBytes.Length, $RemoteEndPoint)

    Write-Host ("SIP request sent to {0}:{1}" -f $RemoteIPAddress, $SIPPort) -ForegroundColor Green

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
        Write-Host "Response received:" -ForegroundColor Green
        Write-Host $ResponseMessage

        # Analyze the response
        if ($ResponseMessage -match "Via: SIP/2.0/UDP .*;rport=.*;branch=") {
            Write-Host "SIP ALG is likely enabled on the gateway. The 'Via' header has been modified." -ForegroundColor Red
        } else {
            Write-Host "SIP ALG is likely disabled. The 'Via' header appears intact." -ForegroundColor Green
        }
    } else {
        Write-Host "No response received from the server. SIP ALG may not be interfering." -ForegroundColor Yellow
    }
} catch {
    Write-Host "An error occurred: $_" -ForegroundColor Red
} finally {
    # Close the UDP client
    $UDPClient.Close()
}
