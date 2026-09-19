# Serves this folder at http://localhost:8765/ using Windows' built-in HttpListener.
# Why: the browser can only remember folder permissions ("Allow on every visit") for a real
# web origin. A page opened as a local file has none, so it asks on every visit.
# The server runs only while the app is open and exits about 90 seconds after the last tab closes.
# It serves files from this folder only and never touches your lyrics folder itself.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
$port = 8765
$url = "http://localhost:$port/"

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)
try { $listener.Start() } catch { Start-Process $url; exit }   # already running: just open the page
Start-Process $url

$types = @{
  '.html' = 'text/html; charset=utf-8'; '.txt' = 'text/plain; charset=utf-8'; '.md' = 'text/plain; charset=utf-8'
  '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.json' = 'application/json'
  '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.ico' = 'image/x-icon'
}
$lastPing = Get-Date
$idleLimit = [TimeSpan]::FromSeconds(90)

while ($listener.IsListening) {
  $task = $listener.GetContextAsync()
  while (-not $task.Wait(1000)) {
    if (((Get-Date) - $lastPing) -gt $idleLimit) { $listener.Stop(); exit }
  }
  $ctx = $task.Result
  $req = $ctx.Request
  $res = $ctx.Response
  try {
    $path = [Uri]::UnescapeDataString($req.Url.AbsolutePath)
    if ($path -eq '/ping') { $lastPing = Get-Date; $res.StatusCode = 204; $res.Close(); continue }
    if ($path -eq '/') { $path = '/index.html' }
    $rel = $path.TrimStart('/') -replace '/', '\'
    $full = [IO.Path]::GetFullPath((Join-Path $root $rel))
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
      $res.StatusCode = 404; $res.Close(); continue
    }
    $bytes = [IO.File]::ReadAllBytes($full)
    $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
    if ($types.ContainsKey($ext)) { $res.ContentType = $types[$ext] } else { $res.ContentType = 'application/octet-stream' }
    $res.Headers.Add('Cache-Control', 'no-store')
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
    $res.Close()
  } catch {
    try { $res.StatusCode = 500; $res.Close() } catch { }
  }
}
