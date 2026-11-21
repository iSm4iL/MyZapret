function Split-ZapretSavedOptions([string]$Text) {
    $items=New-Object Collections.Generic.List[string]
    $word=New-Object Text.StringBuilder;$quote=[char]0;$started=$false
    for($i=0;$i -lt $Text.Length;$i++){
        $c=$Text[$i]
        if($quote -ne [char]0){if($c -eq $quote){$quote=[char]0}else{[void]$word.Append($c)};$started=$true;continue}
        if($c -eq "'" -or $c -eq '"'){$quote=$c;$started=$true;continue}
        if($c -eq '\' -and $i+1 -lt $Text.Length){$i++;[void]$word.Append($Text[$i]);$started=$true;continue}
        if([char]::IsWhiteSpace($c)){if($started){$items.Add($word.ToString());[void]$word.Clear();$started=$false};continue}
        [void]$word.Append($c);$started=$true
    }
    if($quote -ne [char]0){throw 'Invalid quoting in saved engine options'}
    if($started){$items.Add($word.ToString())}
    return $items.ToArray()
}
function Quote-ZapretArgument([string]$Value){
    if($Value -and $Value -notmatch '[\s"]'){return $Value}
    return '"'+([regex]::Replace([regex]::Replace($Value,'(\\*)"','${1}${1}\"'),'(\\+)$','${1}${1}'))+'"'
}
function ConvertTo-ZapretServiceCommand([string]$Image,[string]$Directory) {
    $match=[regex]::Match($Image,'^\s*(?:"([^"]+)"|(\S+))\s+(.+)$')
    if(-not $match.Success){return $Image}
    $exe=if($match.Groups[1].Success){$match.Groups[1].Value}else{$match.Groups[2].Value}
    $arguments=$match.Groups[3].Value
    $old=[regex]::Match($arguments,'^"?@([^"\r\n]+)"?$')
    if($old.Success){
        $options=Split-ZapretSavedOptions ([IO.File]::ReadAllText($old.Groups[1].Value))
        $arguments=($options|ForEach-Object {Quote-ZapretArgument $_}) -join ' '
    }
    if($Image.Length -lt 2000 -and -not $old.Success){return $Image}
    $wrapper=Join-Path $PSScriptRoot 'engine-service.exe'
    if(-not(Test-Path $wrapper)){throw 'Missing engine-service.exe'}
    $config=[ordered]@{FileName=$exe;Arguments=$arguments;WorkingDirectory=(Split-Path $exe)}|ConvertTo-Json -Compress
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$id=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($config)))).Replace('-','').Substring(0,20)}finally{$sha.Dispose()}
    [void][IO.Directory]::CreateDirectory($Directory)
    $path=Join-Path $Directory ($id+'.json')
    if([IO.File]::Exists($path)){
        if([IO.File]::ReadAllText($path) -cne $config){throw 'Saved engine configuration was modified'}
    }else{[IO.File]::WriteAllText($path,$config,[Text.UTF8Encoding]::new($false))}
    return (Quote-ZapretArgument $wrapper)+' '+(Quote-ZapretArgument $path)
}
function Set-ZapretServiceCommand([string]$Name,[string]$Image){
    if(-not ('MyZapret.ServiceConfig' -as [type])){
        Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace MyZapret {
public static class ServiceConfig {
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenSCManager(string m,string d,uint a);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenService(IntPtr m,string n,uint a);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool ChangeServiceConfig(IntPtr s,uint t,uint st,uint e,string b,string g,IntPtr tag,string dep,string account,string pass,string display);
 [DllImport("advapi32.dll")] static extern bool CloseServiceHandle(IntPtr h);
 public static void Set(string name,string image){
  IntPtr manager=OpenSCManager(null,null,1),service=IntPtr.Zero;
  if(manager==IntPtr.Zero)throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  try{
   service=OpenService(manager,name,2);
   if(service==IntPtr.Zero || !ChangeServiceConfig(service,uint.MaxValue,uint.MaxValue,uint.MaxValue,image,null,IntPtr.Zero,null,null,null,null))
    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  }finally{if(service!=IntPtr.Zero)CloseServiceHandle(service);CloseServiceHandle(manager);}
 }
}}
'@
    }
    [MyZapret.ServiceConfig]::Set($Name,$Image)
}
