param(
    [ValidateSet('Enable', 'Restore', 'Status')]
    [string]$Action = 'Enable',
    [switch]$PauseAtEnd
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

function Test-SimplifiedChinese {
    param([System.Globalization.CultureInfo]$Culture)
    while ($Culture.Name) {
        if ($Culture.Name -eq 'zh-Hans') { return $true }
        $Culture = $Culture.Parent
    }
    return $false
}

$UseChinese = Test-SimplifiedChinese ([System.Globalization.CultureInfo]::CurrentUICulture)

function Get-Text {
    param([string]$Chinese, [string]$English)
    if ($UseChinese) { return $Chinese }
    return $English
}

$FlagFunction = @'
function changeFlags(storage, action, useChinese = false) {
  const text = (zh, en) => useChinese ? zh : en;
  const key = 'jetski.developer.customFlagOverrides';
  const backupKey = 'antigravity.branch-switch.backup.v1';
  const names = ['enable-conversation-forking', 'enable-fork-at-historical-step'];
  function parse(raw) {
    try {
      const value = JSON.parse(raw);
      if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
      return value;
    } catch {
      throw new Error(text('本地开关数据格式不正确，已停止操作。', 'Invalid local flag data; stopped.'));
    }
  }
  const raw = storage.getItem(key);
  const flags = raw === null ? {} : parse(raw);
  const saved = storage.getItem(backupKey);
  for (const name of names) {
    if (Object.hasOwn(flags, name) && typeof flags[name] !== 'boolean') {
      throw new Error(text('已有分支开关不是布尔值，已停止操作。', 'Existing branch flag is not boolean; stopped.'));
    }
  }
  let backup;
  if (saved !== null && action !== 'status') {
    backup = parse(saved);
    if (typeof backup.keyExisted !== 'boolean' || !backup.values || typeof backup.values !== 'object' || Array.isArray(backup.values) ||
        Object.entries(backup.values).some(([name, value]) => !names.includes(name) || typeof value !== 'boolean')) {
      throw new Error(text('原值备份格式不正确，已停止操作。', 'Invalid backup data; stopped.'));
    }
  }
  if (action === 'enable') {
    if (saved === null) {
      const values = Object.fromEntries(names.filter(name => Object.hasOwn(flags, name)).map(name => [name, flags[name]]));
      storage.setItem(backupKey, JSON.stringify({ keyExisted: raw !== null, values }));
    }
    for (const name of names) flags[name] = true;
    storage.setItem(key, JSON.stringify(flags));
  } else if (action === 'restore') {
    if (saved === null) throw new Error(text('没有本工具保存的原值，未修改任何开关。', 'No saved original values; no flags changed.'));
    for (const name of names) {
      if (Object.hasOwn(backup.values, name)) flags[name] = backup.values[name];
      else delete flags[name];
    }
    if (!backup.keyExisted && Object.keys(flags).length === 0) storage.removeItem(key);
    else storage.setItem(key, JSON.stringify(flags));
    storage.removeItem(backupKey);
  } else if (action !== 'status') {
    throw new Error(text('不支持的操作。', 'Unsupported action.'));
  }
  return {
    action,
    overrides: Object.fromEntries(names.map(name => [name, Object.hasOwn(flags, name) ? flags[name] : null])),
    hasBackup: storage.getItem(backupKey) !== null,
  };
}
'@

function Get-LocalJson {
    param([int]$Port)
    $request = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$Port/json/list")
    $request.Proxy = $null
    $request.AllowAutoRedirect = $false
    $request.Timeout = 5000
    $request.ReadWriteTimeout = 5000
    $response = $null
    $reader = $null
    try {
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        return ($reader.ReadToEnd() | ConvertFrom-Json)
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
    }
}

function Invoke-WindowExpression {
    param([uri]$Endpoint, [string]$Expression)
    $socket = New-Object System.Net.WebSockets.ClientWebSocket
    $cancel = New-Object System.Threading.CancellationTokenSource
    $cancel.CancelAfter(10000)
    try {
        $socket.ConnectAsync($Endpoint, $cancel.Token).GetAwaiter().GetResult()
        $message = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $Expression; returnByValue = $true } } | ConvertTo-Json -Depth 5 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($message)
        $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$bytes)
        $socket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cancel.Token).GetAwaiter().GetResult()
        $buffer = New-Object byte[] 16384
        $incoming = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$buffer)
        while ($true) {
            $stream = New-Object System.IO.MemoryStream
            try {
                do {
                    $frame = $socket.ReceiveAsync($incoming, $cancel.Token).GetAwaiter().GetResult()
                    if ($frame.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                        throw (Get-Text 'Antigravity 窗口连接已关闭。' 'Antigravity window connection closed.')
                    }
                    $stream.Write($buffer, 0, $frame.Count)
                } until ($frame.EndOfMessage)
                $reply = [System.Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
            } finally { $stream.Dispose() }
            if ($reply.id -ne 1) { continue }
            if ($null -ne $reply.error) { throw (Get-Text '本地调试接口拒绝了请求。' 'Local debugging interface rejected the request.') }
            if ($null -ne $reply.result.exceptionDetails) {
                $reason = $reply.result.exceptionDetails.exception.description
                if ([string]::IsNullOrEmpty($reason)) { $reason = (Get-Text '应用窗口执行失败。' 'Execution in the app window failed.') }
                throw $reason
            }
            if ($null -eq $reply.result.result.value) { throw (Get-Text '应用窗口未返回有效结果。' 'No valid result from the app window.') }
            return $reply.result.result.value
        }
    } finally {
        $socket.Abort()
        $socket.Dispose()
        $cancel.Dispose()
    }
}

try {
    $Host.UI.RawUI.WindowTitle = (Get-Text 'Antigravity 对话分支' 'Antigravity Conversation Branching')
    Write-Host (Get-Text 'Antigravity 对话分支开关' 'Antigravity Conversation Branch Switch')
    $actionLabel = switch ($Action) {
        'Enable' { (Get-Text '启用分支' 'Enable branching') }
        'Restore' { (Get-Text '恢复原值' 'Restore original values') }
        'Status' { (Get-Text '检查状态（只读）' 'Check status (read-only)') }
    }
    Write-Host ((Get-Text '操作：{0}' 'Action: {0}') -f $actionLabel)
    Write-Host ''
    if ($PSVersionTable.PSVersion -lt [version]'5.1') { throw (Get-Text '需要 Windows PowerShell 5.1 或更新版本。' 'Windows PowerShell 5.1 or later is required.') }
    $profileDir = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Antigravity'
    $portFile = Join-Path $profileDir 'DevToolsActivePort'
    if (-not (Test-Path -LiteralPath $portFile -PathType Leaf)) { throw (Get-Text '没有找到 Antigravity 本地调试入口，请先打开桌面应用。' 'Local debugging entry not found; open the desktop app first.') }
    $portLines = [System.IO.File]::ReadAllLines($portFile)
    $debugPort = 0
    if ($portLines.Count -eq 0 -or -not [int]::TryParse($portLines[0], [ref]$debugPort) -or $debugPort -lt 1 -or $debugPort -gt 65535) {
        throw (Get-Text '本地调试端口无效，请重新打开 Antigravity 后检查状态。' 'Invalid debugging port; reopen Antigravity and check status.')
    }
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $debugPort -ErrorAction SilentlyContinue)
    if ($listeners.Count -eq 0) { throw (Get-Text 'Antigravity 尚未提供本地调试服务，请先打开应用并等待主界面加载完成。' 'Debugging service unavailable; open the app and wait for its main window.') }
    foreach ($listener in $listeners) {
        if ($listener.LocalAddress -ne '127.0.0.1' -and $listener.LocalAddress -ne '::1') { throw (Get-Text '调试端口不是仅限本机的入口，已停止。' 'Debugging port is not loopback-only; stopped.') }
        $owner = Get-Process -Id $listener.OwningProcess
        if ($owner.ProcessName -ne 'Antigravity') { throw (Get-Text '调试端口不属于 Antigravity，已停止。' 'Debugging port does not belong to Antigravity; stopped.') }
    }
    $targets = @(Get-LocalJson -Port $debugPort | Where-Object {
        $pageUri = $null
        $_.type -eq 'page' -and [uri]::TryCreate($_.url, [System.UriKind]::Absolute, [ref]$pageUri) -and
        $pageUri.Scheme -eq 'https' -and $pageUri.Host -eq '127.0.0.1' -and
        ($pageUri.AbsolutePath -eq '/' -or $pageUri.AbsolutePath -match '^/c/[^/]+/?$')
    })
    if ($targets.Count -eq 0) { throw (Get-Text '未找到 Antigravity 主页面，请等待主界面或对话加载完成。' 'Main page not found; wait for the home page or conversation to load.') }
    if ($targets.Count -gt 1) { throw (Get-Text '请只保留一个 Antigravity 主窗口，然后重试。' 'Keep exactly one Antigravity main window open, then retry.') }
    $endpoint = $null
    if (-not [uri]::TryCreate($targets[0].webSocketDebuggerUrl, [System.UriKind]::Absolute, [ref]$endpoint) -or
        $endpoint.Scheme -ne 'ws' -or $endpoint.Host -ne '127.0.0.1' -or $endpoint.Port -ne $debugPort) {
        throw (Get-Text '窗口调试地址不是预期的本机地址，已停止。' 'Unexpected window debugging address; stopped.')
    }
    $actionJson = $Action.ToLowerInvariant() | ConvertTo-Json -Compress
    $languageJson = $UseChinese | ConvertTo-Json -Compress
    $wrongPageJson = (Get-Text '当前页面不是 Antigravity 桌面主界面。' 'This page is not the Antigravity desktop main window.') | ConvertTo-Json -Compress
    $expression = @"
(() => {
  if (!window.__APP_CONFIG__?.appVersion || !window.electronNative) throw new Error($wrongPageJson);
  const key = 'jetski.developer.customFlagOverrides';
  const before = localStorage.getItem(key);
  const result = ($FlagFunction)(localStorage, $actionJson, $languageJson);
  const after = localStorage.getItem(key);
  if (before !== after) window.dispatchEvent(new StorageEvent('storage', { key, oldValue: before, newValue: after, storageArea: localStorage }));
  return { ...result, version: window.__APP_CONFIG__.appVersion };
})()
"@
    $result = Invoke-WindowExpression -Endpoint $endpoint -Expression $expression
    Write-Host ("Antigravity {0}" -f $result.version)
    foreach ($entry in $result.overrides.PSObject.Properties) {
        $label = (Get-Text '未覆盖，沿用应用默认值' 'No override; app default')
        if ($null -ne $entry.Value) {
            if ($entry.Value) { $label = (Get-Text '已设为开启' 'Set to enabled') } else { $label = (Get-Text '已设为关闭' 'Set to disabled') }
        }
        $flagLabel = if ($entry.Name -eq 'enable-conversation-forking') { (Get-Text '对话分支' 'Conversation branching') } else { (Get-Text '历史消息分支' 'Historical-step branching') }
        Write-Host ("{0}: {1}" -f $flagLabel, $label)
    }
    $backupLabel = (Get-Text '否' 'No')
    if ($result.hasBackup) { $backupLabel = (Get-Text '是' 'Yes') }
    Write-Host ((Get-Text '可恢复原值：{0}' 'Original values saved: {0}') -f $backupLabel)
    if ($Action -eq 'Enable') {
        Write-Host (Get-Text '已写入开关。请重新打开对话右键菜单，检查 Fork 入口；实际分叉仍需验证。' 'Flags saved. Reopen the conversation context menu and check for Fork; actual branching is not verified.')
    }
    if ($Action -eq 'Restore') { Write-Host (Get-Text '已恢复这两个开关的原值，其他开关保留。' 'Original values restored; other flags preserved.') }
    exit 0
} catch {
    Write-Host ((Get-Text '操作未完成：{0}' 'Operation incomplete: {0}') -f $_.Exception.Message) -ForegroundColor Red
    Write-Host (Get-Text '若操作中途断开，请先运行 check-status.cmd 确认状态，再决定是否重试。' 'If interrupted, run check-status.cmd before deciding whether to retry.')
    exit 1
} finally {
    if ($PauseAtEnd) {
        Write-Host ''
        Write-Host (Get-Text '按 Enter 关闭窗口' 'Press Enter to close')
        [void][Console]::ReadLine()
    }
}
