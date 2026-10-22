# Runs the agent with each kind of wrong setting, then with the right one.
# Run from the root of flutter-review-agent, with your real Gemini key in
# FLUTTER_REVIEW_API_KEY. The key itself is never printed.

$realKey = $env:FLUTTER_REVIEW_API_KEY
if (-not $realKey) {
  Write-Host 'Set FLUTTER_REVIEW_API_KEY to your Gemini key first.'
  exit 1
}

function Run-Case([string]$title, [string[]]$extra) {
  "=== $title"
  $start = Get-Date
  $output = & dart run flutter_review --diff eval/cases/P1-flag.diff @extra 2>&1
  $output | ForEach-Object { "$_" } | Where-Object { $_ -notmatch '^Built|^Building' }
  "exit code: $LASTEXITCODE"
  "time: {0:N1} s" -f ((Get-Date) - $start).TotalSeconds
  ''
}

& {
  # 1. No key at all.
  Remove-Item Env:FLUTTER_REVIEW_API_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:FLUTTER_REVIEW_PROVIDER -ErrorAction SilentlyContinue
  Run-Case '1. no key, no provider' @()

  # 2. A key, but no provider.
  $env:FLUTTER_REVIEW_API_KEY = $realKey
  Run-Case '2. key, no provider' @()

  # 3. A provider the agent has no preset for, and no address.
  $env:FLUTTER_REVIEW_PROVIDER = 'mistral'
  Run-Case '3. key, unknown provider' @()

  # 4. The Gemini key sent to another provider (Groq).
  Run-Case '4. Gemini key sent to Groq' @('--provider', 'groq', '--base-url', 'https://api.groq.com/openai/v1', '--model', 'llama-3.1-8b-instant')

  # 4b. The Gemini key sent to OpenAI, an experimental preset.
  Run-Case '4b. Gemini key sent to OpenAI' @('--provider', 'openai')

  # 5. The right provider, but a key that is not valid.
  $env:FLUTTER_REVIEW_API_KEY = 'not-a-real-key'
  $env:FLUTTER_REVIEW_PROVIDER = 'gemini'
  Run-Case '5. gemini, wrong key' @()

  # 6. The right provider and key, but a model that does not exist first.
  $env:FLUTTER_REVIEW_API_KEY = $realKey
  Run-Case '6. gemini, first model does not exist' @('--model', 'gemini-does-not-exist,gemini-3.8-flash,gemini-3.5-flash')

  # 7. Everything right.
  Run-Case '7. gemini, right key' @()
} | Out-File -Encoding utf8 eval/results/config-cases.txt

Write-Host 'Done. See eval/results/config-cases.txt'
