# Image generation (GPT Image 2.5): hard $3.00 budget

Nothing here runs by itself, and nothing can call OpenAI until a key exists.

## 1. Give it the key (never paste it into chat or into any project file)
Run this in **your own** PowerShell window. It asks for the key without showing it and
stores it **outside the project** at `%USERPROFILE%\.trotro_rush\openai_api_key`:

```powershell
$k = Read-Host "Paste OpenAI API key" -AsSecureString; New-Item -ItemType Directory -Force "$env:USERPROFILE\.trotro_rush" | Out-Null; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($k)) | Set-Content -NoNewline "$env:USERPROFILE\.trotro_rush\openai_api_key"
```

Alternatively set the `OPENAI_API_KEY` environment variable. The script checks the variable first, then the file.
To remove the key later, delete that file.

## 2. Commands
```
python tools/imagegen/imagegen.py status                 # spend so far, key present?  (no API calls)
python tools/imagegen/imagegen.py plan                   # queued jobs + cost estimates (no API calls)
python tools/imagegen/imagegen.py run --max-priority 1   # generate priority-1 jobs only
godot --headless --path . --script res://scripts/tools/process_generated_images.gd   # raw -> game sprites
```

## 3. Budget rules (enforced in imagegen.py)
- Model `gpt-image-2.5-flare`, quality **low** only. Jobs cannot raise quality.
- Hard ceiling **$3.00**, with **$0.50** held back that only priority-1 jobs may use.
- OpenAI bills GPT Image 2.5 by tokens and publishes no per-image price. Until real calls exist, each image is assumed to cost $0.03 (generate) or $0.04 (edit). After that, each estimate is 1.3× the highest real cost seen for the same size and mode.
- A job runs only if `spent + estimate` stays under the ceiling; otherwise the run **stops**.
- A "pending" entry is written to `ledger.json` before each request. Calls that time out are counted at their estimate. HTTP errors are counted at $0, because OpenAI doesn't bill failed requests. No automatic retries.

## Files
- `config.json`: model, quality, budget, pricing (no secrets)
- `jobs.json`: the prioritized asset plan (see docs/ASSET_AUDIT.md)
- `ledger.json`: every generation and its cost (created on first run; no secrets)
- `raw/`: untouched API outputs
