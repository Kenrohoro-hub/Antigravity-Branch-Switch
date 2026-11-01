import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const source = fs.readFileSync(new URL('./branch-switch.ps1', import.meta.url), 'utf8');
const payload = source.match(/\$FlagFunction = @'\r?\n([\s\S]*?)\r?\n'@/)[1];
const changeFlags = vm.runInThisContext(`(${payload})`);

test('portable scripts keep PS5 Chinese encoding and ASCII launchers', () => {
  const bytes = fs.readFileSync(new URL('./branch-switch.ps1', import.meta.url));
  assert.deepEqual([...bytes.subarray(0, 3)], [0xef, 0xbb, 0xbf]);
  for (const file of ['启动Start.cmd', 'restore.cmd', 'check-status.cmd']) {
    assert.ok(fs.readFileSync(new URL(file, import.meta.url)).every(byte => byte < 128));
  }
  assert.ok(!source.includes(' / '));
});

test('PS5 uses simplified Chinese UI cultures only, not regional formats', () => {
  const scriptPath = fileURLToPath(new URL('./branch-switch.ps1', import.meta.url)).replaceAll("'", "''");
  const command = `
    $ErrorActionPreference = 'Stop'
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile('${scriptPath}', [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    $definitions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Test-SimplifiedChinese', 'Get-Text') }, $false)
    foreach ($definition in $definitions) { . ([scriptblock]::Create($definition.Extent.Text)) }
    $results = foreach ($name in @('zh-CN', 'zh-SG', 'zh-Hans', 'zh-Hans-CN', 'zh-TW', 'zh-HK', 'zh-Hant', 'en-US', 'ja-JP')) {
      [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('zh-CN')
      [Threading.Thread]::CurrentThread.CurrentUICulture = [Globalization.CultureInfo]::GetCultureInfo($name)
      $UseChinese = Test-SimplifiedChinese ([Globalization.CultureInfo]::CurrentUICulture)
      [pscustomobject]@{ culture = $name; text = (Get-Text '中文' 'English') }
    }
    $results | ConvertTo-Json -Compress
  `;
  const result = spawnSync(path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe'),
    ['-NoProfile', '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr || String(result.error));
  for (const { culture, text } of JSON.parse(result.stdout)) {
    assert.equal(text, ['zh-CN', 'zh-SG', 'zh-Hans', 'zh-Hans-CN'].includes(culture) ? '中文' : 'English', culture);
  }
});

const key = 'jetski.developer.customFlagOverrides';
const fork = 'enable-conversation-forking';
const historical = 'enable-fork-at-historical-step';
function storage(initial = {}) {
  const items = new Map(Object.entries(initial));
  return { getItem: name => items.get(name) ?? null, setItem: (name, value) => items.set(name, value), removeItem: name => items.delete(name) };
}

test('status is read-only; enable then restore preserves original absence', () => {
  const data = storage();
  assert.equal(changeFlags(data, 'status').hasBackup, false);
  assert.equal(data.getItem(key), null);
  assert.equal(changeFlags(data, 'enable').overrides[fork], true);
  assert.equal(changeFlags(data, 'enable').hasBackup, true);
  assert.equal(changeFlags(data, 'restore').hasBackup, false);
  assert.equal(data.getItem(key), null);
});

test('restore preserves existing false, true and unrelated later changes', () => {
  const data = storage({ [key]: JSON.stringify({ [fork]: false, [historical]: true, unrelated: true }) });
  changeFlags(data, 'enable');
  data.setItem(key, JSON.stringify({ ...JSON.parse(data.getItem(key)), unrelated: false, addedLater: true }));
  changeFlags(data, 'enable');
  changeFlags(data, 'restore');
  assert.deepEqual(JSON.parse(data.getItem(key)), { [fork]: false, [historical]: true, unrelated: false, addedLater: true });
});

test('invalid data and missing backup do not overwrite settings', () => {
  for (const raw of ['broken', '[]', JSON.stringify({ [fork]: 'false' })]) {
    const data = storage({ [key]: raw });
    assert.throws(() => changeFlags(data, 'enable'));
    assert.equal(data.getItem(key), raw);
  }
  assert.throws(() => changeFlags(storage(), 'restore'));
  const corruptBackup = storage({ [key]: '{}', 'antigravity.branch-switch.backup.v1': 'broken' });
  assert.throws(() => changeFlags(corruptBackup, 'enable'));
  assert.equal(corruptBackup.getItem(key), '{}');
});

test('flag errors use the selected language without bilingual output', () => {
  for (const chinese of [true, false]) {
    assert.throws(() => changeFlags(storage({ [key]: 'broken' }), 'enable', chinese),
      { message: chinese ? '本地开关数据格式不正确，已停止操作。' : 'Invalid local flag data; stopped.' });
    assert.throws(() => changeFlags(storage(), 'restore', chinese),
      { message: chinese ? '没有本工具保存的原值，未修改任何开关。' : 'No saved original values; no flags changed.' });
  }
});
