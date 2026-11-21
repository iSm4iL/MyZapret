$ErrorActionPreference='Stop'
. "$PSScriptRoot/builder-core.ps1"
$report=Join-Path "$PackageRoot/reports" ('Discord-HTTPS-'+(Get-Date -Format yyyyMMdd-HHmmss))
[void][IO.Directory]::CreateDirectory($report)
$state="$BuilderDir/discord-https-check.json"
$guard=$null
try {
    BSave @{State='Waiting';PID=$PID;Report=$report} $state
    $deadline=[datetime]::UtcNow.AddHours(2)
    while(Vpn-Connected){
        if([datetime]::UtcNow -ge $deadline){throw 'VPN не отключён за время ожидания'}
        Start-Sleep -Seconds 2
    }
    $guard=BControlLock 45000
    if(-not $guard){throw 'Служба занята'}
    if(Vpn-Connected){throw 'VPN снова включён'}
    BSave @{State='Running';PID=$PID;Report=$report} $state
    $active=BRead $BuilderActive
    BFollowStep | Set-Content "$report/service.txt" -Encoding UTF8
    if((Get-Service $BuilderService).Status -ne 'Running' -or -not (Get-Process winws,winws2 -ErrorAction SilentlyContinue)){throw 'Движок не запущен, HTTPS-результаты были бы недостоверны'}
    $rows=foreach($url in @('https://discord.com/api/v10/gateway','https://gateway.discord.gg/','https://cdn.discordapp.com/','https://updates.discord.com/','https://www.youtube.com/','https://www.google.com/generate_204')){
        $name=([uri]$url).Host
        $ips=@(Resolve-DnsName -Name $name -Type A -DnsOnly -NoHostsFile -ErrorAction SilentlyContinue|Where-Object IPAddress|Select-Object -ExpandProperty IPAddress -Unique|Select-Object -First 2)
        foreach($ip in (@('system')+$ips)){
            if(Vpn-Connected -or (Get-Service $BuilderService).Status -ne 'Running'){throw 'VPN или служба изменили состояние во время прогона'}
            $argsList=@('-q','-4','--noproxy','*','-sS','--connect-timeout','4','--max-time','7','-o','NUL','-w','%{http_code} %{remote_ip} %{time_connect} %{time_appconnect}')
            if($ip -ne 'system'){$argsList+=@('--resolve',"${name}:443:$ip")}
            $result=& { $ErrorActionPreference="Continue"; curl.exe @argsList $url 2>> "$report/curl-errors.txt" }
            [pscustomobject]@{Host=$name;Address=$ip;Exit=$LASTEXITCODE;Result=$result}
        }
    }
    if(Vpn-Connected){throw 'VPN включился, результат недействителен'}
    $rows|Export-Csv "$report/results.csv" -NoTypeInformation -Encoding UTF8
    BSave @{State='Complete';PID=$PID;Report=$report;Model=$active.Model.Name} $state
}catch{BSave @{State='Failed';PID=$PID;Report=$report;Error=$_.Exception.Message} $state}
finally{if($guard){$guard.Dispose()}}