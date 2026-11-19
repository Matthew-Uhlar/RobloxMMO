param([Parameter(Mandatory=$true)][string]$ScenePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$scene=Get-Content -LiteralPath $ScenePath -Raw | ConvertFrom-Json
$scale=2
$bitmap=New-Object System.Drawing.Bitmap ($scene.width*$scale),($scene.height*$scale)
$g=[System.Drawing.Graphics]::FromImage($bitmap)
$g.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint=[System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.ScaleTransform($scale,$scale)
function Color([string]$hex){
 if($hex.Length -eq 9){return [System.Drawing.Color]::FromArgb([Convert]::ToInt32($hex.Substring(1,2),16),[Convert]::ToInt32($hex.Substring(3,2),16),[Convert]::ToInt32($hex.Substring(5,2),16),[Convert]::ToInt32($hex.Substring(7,2),16))}
 return [System.Drawing.ColorTranslator]::FromHtml($hex)
}
foreach($cmd in $scene.commands){
 if($cmd.type -eq 'gradient'){
  $rect=New-Object System.Drawing.Rectangle 0,0,$scene.width,$scene.height
  $brush=New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect,(Color $cmd.top),(Color $cmd.bottom),90
  $g.FillRectangle($brush,$rect);$brush.Dispose();continue
 }
 $brush=New-Object System.Drawing.SolidBrush (Color $cmd.color)
 switch($cmd.type){
  'ellipse' {$g.FillEllipse($brush,[single]$cmd.x,[single]$cmd.y,[single]$cmd.w,[single]$cmd.h)}
  'polygon' {
   $points=[System.Drawing.PointF[]]@($cmd.points | ForEach-Object {New-Object System.Drawing.PointF ([single]$_[0]),([single]$_[1])})
   $g.FillPolygon($brush,$points)
  }
  'line' {$pen=New-Object System.Drawing.Pen (Color $cmd.color),([single]$cmd.width);$g.DrawLine($pen,[single]$cmd.x1,[single]$cmd.y1,[single]$cmd.x2,[single]$cmd.y2);$pen.Dispose()}
  'text' {
   $style=if($cmd.bold){[System.Drawing.FontStyle]::Bold}else{[System.Drawing.FontStyle]::Regular}
   $font=New-Object System.Drawing.Font $cmd.font,([single]$cmd.size),$style,([System.Drawing.GraphicsUnit]::Pixel)
   $g.DrawString($cmd.value,$font,$brush,[single]$cmd.x,[single]$cmd.y);$font.Dispose()
  }
 }
 $brush.Dispose()
}
$g.Dispose()
$final=New-Object System.Drawing.Bitmap $scene.width,$scene.height
$resize=[System.Drawing.Graphics]::FromImage($final)
$resize.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$resize.DrawImage($bitmap,0,0,$scene.width,$scene.height)
$resize.Dispose();$bitmap.Dispose()
$final.Save($OutputPath,[System.Drawing.Imaging.ImageFormat]::Png)
$final.Dispose()
