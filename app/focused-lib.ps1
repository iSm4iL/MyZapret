function BFProxyStart([string]$mode,[string]$directory){
    if($mode -notin @('sni','record1','record5','tcp')){throw 'Unknown TLS proxy mode'}
    $status=Join-Path $directory ('proxy-'+$mode+'.json')
    if(Test-Path -LiteralPath $status){Remove-Item -LiteralPath $status}
    $node=(Get-Command node.exe -ErrorAction Stop).Source
    $p=Start-Process $node -ArgumentList ('"'+$BuilderLab+'\tls-record-proxy.cjs" '+$mode+' 0 "'+$status+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput "$status.out" -RedirectStandardError "$status.err"
    $null=$p.Handle
    for($i=0;$i -lt 30 -and -not(Test-Path $status) -and -not $p.HasExited;$i++){Start-Sleep -Milliseconds 100}
    if(-not(Test-Path $status)){if(-not $p.HasExited){$p.Kill()};$p.Dispose();throw 'Локальный TLS-прокси не запустился.'}
    return [pscustomobject]@{Process=$p;Status=(BRead $status)}
}
function BFImages([string]$ip){
    if([Net.IPAddress]::Parse($ip).AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork){throw 'Focused methods require IPv4'}
    $head='"'+$PackageRoot+'\bin\winws2.exe" --wf-tcp-out 443 --wf-tcp-in 443 --wf-raw-filter "ip and (ip.SrcAddr == '+$ip+' or ip.DstAddr == '+$ip+')" --lua-init "@'+$PackageRoot+'\lua\zapret-lib.lua" --lua-init "@'+$PackageRoot+'\lua\zapret-antidpi.lua" --filter-tcp 443 --ipset-ip '+$ip+' '
    $window='--out-range -n15 --payload empty,unknown,tls_client_hello --lua-desync wssize:wsize={0}:scale={1}:forced_cutoff=tls_client_hello --payload tls_client_hello --lua-desync multisplit:pos=1,midsld'
    foreach($size in @(1,16,64)){$scale=if($size -eq 1){6}else{0};[pscustomobject]@{Name="window-$size-scale$scale";Image=($head+($window -f $size,$scale))}}
    foreach($blob in @('0x00000000000000000000000000000000','fake_default_tls')){[pscustomobject]@{Name=('syndata-'+$(if($blob -eq 'fake_default_tls'){'tls'}else{'zeros'}));Image=($head+'--out-range -n15 --payload empty,unknown,tls_client_hello --lua-desync syndata:blob='+$blob+' --payload tls_client_hello --lua-desync multisplit:pos=1,midsld')}}
    foreach($id in @('zero','rnd','seq')){[pscustomobject]@{Name="ip-id-$id";Image=($head+'--out-range -n15 --payload tls_client_hello --lua-desync multisplit:pos=10:seqovl=1:ip_id='+$id+' --payload unknown,empty --lua-desync send:ip_id='+$id+' --lua-desync drop')}}
    [pscustomobject]@{Name='ip-fragment-32';Image=($head+'--out-range -d5 --payload tls_client_hello --lua-desync send:ipfrag:ipfrag_pos_tcp=32 --lua-desync drop')}
    [pscustomobject]@{Name='tcp-oob-1';Image=($head+'--out-range -d5 --payload tls_client_hello --lua-desync oob:pos=1')}
}
function BFPacketTool($arguments){
    $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName='pktmon.exe'
    $info.Arguments=($arguments|ForEach-Object {'"'+$_+'"'}) -join ' '
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.StandardOutputEncoding=[Text.Encoding]::UTF8;$info.StandardErrorEncoding=[Text.Encoding]::UTF8
    $p=New-Object Diagnostics.Process;$p.StartInfo=$info
    try{[void]$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit(15000)){$p.Kill();throw 'Pktmon command timed out'};return [pscustomobject]@{Code=$p.ExitCode;Text=($o.Result+"`n"+$e.Result)}}finally{$p.Dispose()}
}
function BFCaptureStart([string]$ip,[string]$directory,[switch]$AllComponents){
    $state=BFPacketTool @('status');$filters=BFPacketTool @('filter','list')
    if($state.Code -ne 0 -or $state.Text -notmatch 'не запущен|not running|stopped' -or $filters.Text -notmatch '(?im)^\s*(Нет|None|No filters)\.?\s*$'){return @{Started=$false;Reason='Pktmon занят или существуют чужие фильтры; захват пропущен.'}}
    $name='MyZapret-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $add=BFPacketTool @('filter','add',$name,'-i',$ip,'-t','TCP','-p','443')
    if($add.Code -ne 0){return @{Started=$false;Reason=$add.Text}}
    $etl=Join-Path $directory 'baseline.etl'
    $components=if($AllComponents){'all'}else{'nics'}
    # ETW uses 16-MB per-CPU buffers here; a small circular file loses the start of the flow.
    $start=BFPacketTool @('start','--capture','--comp',$components,'--pkt-size','192','--file-size','512','--file-name',$etl)
    if($start.Code -ne 0){[void](BFPacketTool @('filter','remove',$name));return @{Started=$false;Reason=$start.Text}}
    return @{Started=$true;Name=$name;ETL=$etl;IP=$ip}
}
function BFCaptureStop($capture,[string]$directory){
    if(-not $capture.Started){return}
    try{
        $stop=BFPacketTool @('stop');$stop.Text|Set-Content "$directory/capture-stop.txt" -Encoding UTF8
        [void](BFPacketTool @('etl2txt',$capture.ETL,'--out',"$directory/baseline.txt",'--hex'))
        [void](BFPacketTool @('etl2pcap',$capture.ETL,'--out',"$directory/baseline.pcapng"))
        if(Test-Path "$directory/baseline.pcapng"){& node.exe "$BuilderLab/pcap-summary.cjs" "$directory/baseline.pcapng" $capture.IP | Set-Content "$directory/packet-summary.json" -Encoding UTF8}
        if(Test-Path "$directory/baseline.txt"){& node.exe "$BuilderLab/pcap-summary.cjs" "$directory/baseline.txt" $capture.IP --text | Set-Content "$directory/packet-summary-all.json" -Encoding UTF8}
    }finally{[void](BFPacketTool @('filter','remove',$capture.Name))}
}
