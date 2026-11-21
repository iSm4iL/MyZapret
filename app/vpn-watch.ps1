$ErrorActionPreference='Stop'
. "$PSScriptRoot/builder-core.ps1"
$singleton=[Threading.Mutex]::new($false,'Global\MyZapretVpnWatcher')
if(-not $singleton.WaitOne(0)){$singleton.Dispose();return}
try{
    while($true){
        $guard=$null
        try{
            $guard=BControlLock
            if($guard){BFollowStep|Out-Null}
        }catch [IO.IOException]{
            # The builder owns the service while applying, stopping or comparing recipes.
        }catch{BFollowStatus ('VPN-авто: '+$_.Exception.Message)|Out-Null}
        finally{if($guard){$guard.Dispose()}}
        Start-Sleep -Seconds 3
    }
}finally{[void]$singleton.ReleaseMutex();$singleton.Dispose()}
