function BImageAssets([string]$Image){
    $files=@([regex]::Matches($Image,'(?:[^\s"]|"[^"]*")+')|ForEach-Object {
        $value=$_.Value.Trim('"');$m=[regex]::Match($value,'[A-Za-z]:[\\/].+$')
        if($m.Success -and (Test-Path -LiteralPath $m.Value -PathType Leaf)){$m.Value}
    })
    return @($files|Sort-Object -Unique|ForEach-Object {[pscustomobject]@{Path=$_;SHA256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}})
}
function BSaveVerifiedProof([string]$Report,[string]$SourceCommandHash){
    $active=BRead $BuilderActive
    if(-not $active -or (BHash $active.ServiceImage) -ne $SourceCommandHash){throw 'Applied composition changed during the test; verification cannot be saved.'}
    foreach($video in @('Default-video','Second-video')){
        $rows=@(Import-Csv (Join-Path $Report ($video+'-transport.csv'))|Where-Object Case -eq 'MyZapret — применённый')
        foreach($mode in @('TLS12','TLS13','H3')){
            $match=@($rows|Where-Object Mode -eq $mode)
            if($match.Count -ne 1 -or $match[0].Pass -ne 'True' -or [int]$match[0].Bytes -lt 16384){throw "No verified video transfer: $video / $mode"}
        }
    }
    BSave @{CommandHash=$SourceCommandHash;ModelHash=$active.ModelHash;Report=$Report;Time=(Get-Date).ToString('s');Assets=@(BImageAssets $active.ServiceImage);Checks=6} "$BuilderDir/verified-default.json"
}
function BVerifiedActive {
    $proof=BRead "$BuilderDir/verified-default.json";$active=BRead $BuilderActive
    if(-not $proof -or -not $active -or $proof.Checks -ne 6 -or $proof.CommandHash -ne (BHash $active.ServiceImage)){throw 'Сначала выполните успешный тест YouTube TCP / QUIC для применённого состава.'}
    foreach($asset in $proof.Assets){
        if(-not(Test-Path -LiteralPath $asset.Path) -or (Get-FileHash -LiteralPath $asset.Path -Algorithm SHA256).Hash -ne $asset.SHA256){throw "Файлы состава изменены; повторите тест: $($asset.Path)"}
    }
    return $active
}
function BSaveInstalledRoot {
    $key="HKLM:/SYSTEM/CurrentControlSet/Services/$BuilderService/Parameters"
    New-Item $key -Force|Out-Null
    Set-ItemProperty $key -Name MyZapretRoot -Value $PackageRoot
}
function BInstallVerifiedDefault {
    $active=BVerifiedActive
    $snapshot=BSnapshot;$follow=BRead "$BuilderDir/vpn-follow.json"
    $task=Get-ScheduledTask -TaskName $FollowTask -ErrorAction SilentlyContinue
    $xml=if($task){Export-ScheduledTask -TaskName $FollowTask}else{$null}
    $draft=BRead $BuilderDraft;$success=$false
    try{
        if(-not(Test-Path $BuilderOriginal)){BSave $snapshot $BuilderOriginal}
        BPause $snapshot -Permanent
        BValidate $active.ServiceImage
        $image=ConvertTo-ZapretServiceCommand $active.ServiceImage "$BuilderDir/service-configs"
        if(Get-Service $BuilderService -ErrorAction SilentlyContinue){Set-ZapretServiceCommand $BuilderService $image}
        else{New-Service -Name $BuilderService -DisplayName 'MyZapret — winws2' -BinaryPathName $image -StartupType Manual|Out-Null}
        Set-Service $BuilderService -StartupType Automatic
        BFollowWant $true
        $newFollow=BRead "$BuilderDir/vpn-follow.json";$newFollow.Enabled=$true;BSave $newFollow "$BuilderDir/vpn-follow.json"
        BFollowInstall
        BFollowStep|Out-Null
        if($draft){BSave $draft "$BuilderDir/draft-before-default.json"}
        BSave $active.Model $BuilderDraft
        BSave @{Service=$BuilderService;Root=$PackageRoot;CommandHash=(BHash $active.ServiceImage);Time=(Get-Date).ToString('s');VPNState=(BVpnState)} "$BuilderDir/default-install.json"
        BSaveInstalledRoot
        $success=$true
        'Проверенный состав сделан основным. Служба: myzapret2; автозапуск Windows и VPN-авто включены. Старые службы и их автозадачи отключены.'
        if(Vpn-Connected){'VPN включён: MyZapret ожидает его отключения.'}else{'VPN выключен: MyZapret запущен.'}
    }finally{
        if(-not $success){
            if(Get-ScheduledTask -TaskName $FollowTask -ErrorAction SilentlyContinue){Disable-ScheduledTask -TaskName $FollowTask|Out-Null;Stop-ScheduledTask -TaskName $FollowTask}
            if($follow){BSave $follow "$BuilderDir/vpn-follow.json"}elseif(Test-Path "$BuilderDir/vpn-follow.json"){Remove-Item "$BuilderDir/vpn-follow.json"}
            BRestore $snapshot $true
            if($xml){Register-ScheduledTask -TaskName $FollowTask -Xml $xml -Force|Out-Null;if($task.State -eq 'Disabled'){Disable-ScheduledTask -TaskName $FollowTask|Out-Null}elseif($task.State -eq 'Running'){Start-ScheduledTask -TaskName $FollowTask}}
            elseif(Get-ScheduledTask -TaskName $FollowTask -ErrorAction SilentlyContinue){Unregister-ScheduledTask -TaskName $FollowTask -Confirm:$false}
        }
    }
}
