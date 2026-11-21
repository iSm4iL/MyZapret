function BWriteCurrentReport($active,$rows,[string]$voice,[string]$directory){
    $display=@(foreach($row in $rows){
        $site=[string]$row.Pass -eq 'True'
        $name=if($BuilderCatalog.Contains([string]$row.Group)){$BuilderCatalog[[string]$row.Group].Label}else{[string]$row.Group}
        $video=if($row.Group -eq 'youtube'){if([string]$row.VideoPass -eq 'True'){'Получен видеофрагмент'}else{'Видеофрагмент НЕ получен'}}else{'—'}
        [pscustomobject]@{
            'Сервис'=$name
            'Страницы'="$($row.Passed)/$($row.Total)"
            'Видео'=$video
            'Результат'=$(if($row.Group -eq 'discord'){if($site){'Доступен только сайт. Голос — отдельный результат выше.'}else{'Сайт недоступен. Голос — отдельный результат выше.'}}elseif($row.Group -eq 'youtube'){$video}elseif($site){'Сайт доступен'}else{'Сайт не прошёл проверку'})
            'Подробности'=[string]$row.Details
        }
    })
    $title=[Net.WebUtility]::HtmlEncode([string]$active.Model.Name)
    $safeVoice=[Net.WebUtility]::HtmlEncode($voice)
    $passed=@($rows|Where-Object {[string]$_.Pass -eq 'True'}).Count
    $display|ConvertTo-Html -Head '<meta charset="utf-8"><style>body{font:15px Segoe UI;margin:24px}td,th{padding:8px;border:1px solid #aaa}table{border-collapse:collapse}th{text-align:left}</style>' -PreContent "<h1>$title</h1><h2>Голос Discord</h2><p>$safeVoice</p><h2>Сайты и видео</h2><p>Успешных проверок сервисов: $passed из $(@($rows).Count). Это НЕ общий результат голоса. У Discord ниже проверяется только сайт, у YouTube — страницы и видеофрагмент. Игровые соединения не проверены.</p>"|Set-Content "$directory/table.html" -Encoding UTF8
}
