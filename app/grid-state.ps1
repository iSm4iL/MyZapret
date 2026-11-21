function BGridState($grid){
    return [pscustomobject]@{
        Row=$(if($grid.CurrentCell){$grid.Rows[$grid.CurrentCell.RowIndex].Tag}else{$null})
        Column=$(if($grid.CurrentCell){$grid.CurrentCell.OwningColumn.Name}else{$null})
        Top=$grid.FirstDisplayedScrollingRowIndex
        Horizontal=$grid.HorizontalScrollingOffset
    }
}
function BGridRows($grid,[object[]]$keys){
    $same=$grid.Rows.Count -eq $keys.Count
    if($same){for($i=0;$i -lt $keys.Count;$i++){if($grid.Rows[$i].Tag -ne $keys[$i]){$same=$false;break}}}
    if($same){return}
    $grid.Rows.Clear()
    foreach($key in $keys){$i=$grid.Rows.Add();$grid.Rows[$i].Tag=$key}
}
function BRestoreGrid($grid,$view){
    if($null -ne $view.Row -and $grid.Columns.Contains([string]$view.Column) -and $grid.Columns[$view.Column].Visible){
        $row=@($grid.Rows|Where-Object {$_.Tag -eq $view.Row}|Select-Object -First 1)
        if($row.Count -and $grid.CurrentCell -ne $row[0].Cells[$view.Column]){$grid.CurrentCell=$row[0].Cells[$view.Column]}
    }
    if($view.Top -ge 0 -and $view.Top -lt $grid.Rows.Count -and $grid.FirstDisplayedScrollingRowIndex -ne $view.Top){$grid.FirstDisplayedScrollingRowIndex=$view.Top}
    if($grid.HorizontalScrollingOffset -ne $view.Horizontal){$grid.HorizontalScrollingOffset=$view.Horizontal}
}
