function BLegacyImage([switch]$StockDiscord) {
    $bundle=Join-Path $PackageRoot 'legacy'
    $manifest=BRead "$bundle/manifest.json"
    if(-not $manifest){throw 'Нет сохранённого старого состава.'}
    foreach($asset in $manifest.Files){
        $path=Join-Path $bundle $asset.Path
        if(-not(Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $asset.Hash){throw "Изменён файл старого состава: $($asset.Path)"}
    }
    $image=([IO.File]::ReadAllText("$bundle/command.txt")).Replace('{LEGACY}',$bundle)
    if($StockDiscord){
        $stock=([IO.File]::ReadAllText("$bundle/discord-stock.txt")).Replace('{LEGACY}',$bundle) -split ' --new '
        $parts=@($image -split ' --new ');$changed=0
        for($i=0;$i -lt $parts.Count;$i++){
            if($parts[$i] -match '--filter-l7 discord,stun'){$parts[$i]=$stock[0];$changed++}
            elseif($parts[$i] -match '--hostlist-domains discord.media'){$parts[$i]=$stock[1];$changed++}
        }
        if($changed -ne 2){throw 'Не найдено ровно два профиля Discord.'}
        return $parts -join ' --new '
    }
    return $image
}
function BInstallStoredPreset([switch]$Previous,[switch]$StockDiscord,$Model){
    $before=BRead $BuilderActive
    $draft=BRead $BuilderDraft
    $oldPrevious=BRead "$BuilderDir/previous.json"
    $follow=BRead "$BuilderDir/vpn-follow.json"
    if($Model){
        $image=BBuild $Model
        $release=Join-Path $BuilderDir ('releases/alt13-'+[guid]::NewGuid().ToString('N'))
        $next=[pscustomobject]@{Model=$Model;ModelHash=(BHash $image);ServiceImage=(BFreeze $image $release);Applied=(Get-Date).ToString('s');Release=$release}
    }elseif($Previous){
        if(-not $oldPrevious){throw 'Нет предыдущего состава.'}
        $next=$oldPrevious
    }else{
        if($before.Model.BaseName -eq 'legacy-saved' -and [bool]$before.Model.LegacyDiscordStock -eq [bool]$StockDiscord){'Старый состав уже выбран.';return}
        $image=BLegacyImage -StockDiscord:$StockDiscord
        $model=[pscustomobject]@{Name='Старый состав — исходный winws';Engine='winws';BaseName='legacy-saved';Selections=@{};GameFilter=$false;IpsetLoaded=$false}
        if($StockDiscord){$model.Name='Обычный zapret — Discord из general.bat';$model|Add-Member -NotePropertyName LegacyDiscordStock -NotePropertyValue $true}
        $next=[pscustomobject]@{Model=$model;ModelHash=(BHash $image);ServiceImage=$image;Applied=(Get-Date).ToString('s');Release=(Join-Path $PackageRoot 'legacy')}
    }
    $snapshot=BSnapshot;$ok=$false
    try{
        BPause $snapshot -Permanent
        BValidate $next.ServiceImage
        $command=ConvertTo-ZapretServiceCommand $next.ServiceImage "$BuilderDir/service-configs"
        if(Get-Service $BuilderService -ErrorAction SilentlyContinue){Set-ZapretServiceCommand $BuilderService $command}
        else{New-Service -Name $BuilderService -DisplayName 'MyZapret' -BinaryPathName $command -StartupType Manual|Out-Null}
        Set-Service $BuilderService -StartupType Automatic
        if($draft -and -not $Previous){BSave $draft "$BuilderDir/pre-legacy-draft.json"}
        if($before){BSave $before "$BuilderDir/previous.json"}
        BSave $next $BuilderActive
        BSave $next.Model $BuilderDraft
        BFollowWant $true
        if(-not(Vpn-Connected)){BRunImage $next.ServiceImage}
        $ok=$true
        "Выбран: $($next.Model.Name). Автозапуск включён. При включённом VPN служба приостановлена. Работа сайтов и голоса ещё не подтверждена."
    }finally{
        if(-not $ok){
            foreach($item in @(@{Path=$BuilderActive;Value=$before},@{Path=$BuilderDraft;Value=$draft},@{Path="$BuilderDir/previous.json";Value=$oldPrevious},@{Path="$BuilderDir/vpn-follow.json";Value=$follow})){
                if($null -ne $item.Value){BSave $item.Value $item.Path}else{Remove-Item -LiteralPath $item.Path -ErrorAction SilentlyContinue}
            }
            BRestore $snapshot $true
        }
    }
}
