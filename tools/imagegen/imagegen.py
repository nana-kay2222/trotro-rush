#!/usr/bin/env python3
"""
Trotro Rush image generation (OpenAI GPT Image 2.5) with a hard spending ceiling.

    python tools/imagegen/imagegen.py status            # budget + ledger summary (no API calls)
    python tools/imagegen/imagegen.py plan              # what would run and what it would cost (no API calls)
    python tools/imagegen/imagegen.py run --max-priority 1   # generate, cheapest-risk first, within budget

Safety rules enforced here (see README.md):
- Quality is always config.quality ("low"); jobs cannot raise it. The only exception is
  "run --job X --quality medium", for a single job the owner explicitly approved.
- Before every call: estimated cost + everything already spent must stay within budget
  (and outside the reserve unless the job is priority 1). Otherwise generation STOPS.
- A "pending" ledger entry is written before each request, so a crash mid-call is still
  counted against the budget.
- The API key comes from the OPENAI_API_KEY environment variable or a key file outside
  the project. It is never printed, logged or written anywhere by this script.
Standard library only.
"""
import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent
CONFIG_PATH = HERE / "config.json"
JOBS_PATH = HERE / "jobs.json"
LEDGER_PATH = HERE / "ledger.json"
RAW_DIR = HERE / "raw"
KEY_FILE = Path.home() / ".trotro_rush" / "openai_api_key"
API_BASE = "https://api.openai.com/v1/images"

_secret = None  # the key, kept only in memory so output can be scrubbed


def load_json(path, default=None):
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8-sig"))  # tolerate a BOM from PowerShell edits


def save_json(path, data):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2), encoding="utf-8")
    # OneDrive briefly locks files while syncing them; retry instead of losing the record.
    for attempt in range(20):
        try:
            tmp.replace(path)
            return
        except PermissionError:
            time.sleep(0.5)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def scrub(text):
    text = str(text)
    if _secret:
        text = text.replace(_secret, "[REDACTED]")
    return text


def say(*parts):
    print(scrub(" ".join(str(p) for p in parts)))


def get_api_key():
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key and KEY_FILE.exists():
        key = KEY_FILE.read_text(encoding="utf-8").strip()
    return key or None


# ---------------------------------------------------------------- budget

def ledger_entries():
    return load_json(LEDGER_PATH, {"entries": []})["entries"]


def charged(entry):
    """What an entry counts against the budget."""
    if entry["status"] == "ok":
        return entry["actual_usd"]
    if entry["status"] in ("pending", "unknown"):
        return entry["estimated_usd"]  # may have been billed; assume it was
    return 0.0  # HTTP errors are not billed


def spent():
    return round(sum(charged(e) for e in ledger_entries()), 4)


def estimate(cfg, job):
    seen = [e["actual_usd"] for e in ledger_entries()
            if e["status"] == "ok" and e["mode"] == job["mode"] and e["size"] == job["size"]
            and e.get("usage_reported") and e.get("quality", "low") == cfg["quality"]]
    if not seen and cfg["quality"] != "low":
        return 0.20  # no medium price seen yet: assume a lot, so the budget check stays safe
    if seen:
        return round(max(seen) * 1.3, 4)
    return cfg["fallback_estimate_usd"][job["mode"]]


def done_job_ids():
    return {e["job"] for e in ledger_entries() if e["status"] == "ok"}


def allowance(cfg, job):
    ceiling = cfg["budget_usd"] if job["priority"] == 1 else cfg["budget_usd"] - cfg["reserve_usd"]
    return round(ceiling - spent(), 4)


# ---------------------------------------------------------------- API

def multipart(fields, files):
    boundary = uuid.uuid4().hex
    body = bytearray()
    for name, value in fields.items():
        body += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n".encode()
    for name, path in files:
        body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"; filename=\"{Path(path).name}\"\r\n"
                 f"Content-Type: image/png\r\n\r\n").encode()
        body += Path(path).read_bytes() + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return bytes(body), f"multipart/form-data; boundary={boundary}"


def call_api(cfg, job, key):
    params = {
        "model": cfg["model"],
        "prompt": job["full_prompt"],
        "size": job["size"],
        "quality": cfg["quality"],
        "n": 1,
        "output_format": "png",
    }
    # Sprites want transparency; textures/backdrops set "background": "opaque" per job.
    background = job.get("background", "transparent" if cfg.get("request_transparent_background") else None)
    if background:
        params["background"] = background
    if job["mode"] == "edit":
        refs = job["reference"] if isinstance(job["reference"], list) else [job["reference"]]
        body, ctype = multipart({k: str(v) for k, v in params.items()}, [("image[]", PROJECT / r) for r in refs])
        url = f"{API_BASE}/edits"
    else:
        body, ctype = json.dumps(params).encode(), "application/json"
        url = f"{API_BASE}/generations"
    req = urllib.request.Request(url, data=body, method="POST",
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": ctype})
    with urllib.request.urlopen(req, timeout=cfg["timeout_seconds"]) as resp:
        return json.loads(resp.read().decode("utf-8"))


def cost_from_usage(cfg, usage):
    rates = cfg["pricing_per_million_tokens"]
    return round((usage.get("input_tokens", 0) * rates["input"] + usage.get("output_tokens", 0) * rates["output"]) / 1e6, 5)


# ---------------------------------------------------------------- commands

def pending_jobs(jobs_doc, max_priority=None, only=None):
    done = done_job_ids()
    jobs = sorted(jobs_doc["jobs"], key=lambda j: j["priority"])
    out = []
    for j in jobs:
        if j["id"] in done:
            continue
        if only and j["id"] != only:
            continue
        if max_priority is not None and j["priority"] > max_priority:
            continue
        j = dict(j)
        style = j.get("style", jobs_doc["style"])  # textures supply their own style text
        j["full_prompt"] = f"{j['prompt']}\n\nStyle: {style}" if style else j["prompt"]
        out.append(j)
    return out


def cmd_status(cfg, _args):
    entries = ledger_entries()
    ok = [e for e in entries if e["status"] == "ok"]
    say(f"Model: {cfg['model']}  quality: {cfg['quality']}")
    say(f"Budget: ${cfg['budget_usd']:.2f}  (reserve ${cfg['reserve_usd']:.2f} for priority-1 only)")
    say(f"Generations completed: {len(ok)}   ledger entries: {len(entries)}")
    say(f"Spent (counted against budget): ${spent():.4f}   remaining: ${cfg['budget_usd'] - spent():.4f}")
    say(f"API key available: {'yes' if get_api_key() else 'NO (nothing can be generated yet)'}")


def cmd_plan(cfg, args):
    jobs_doc = load_json(JOBS_PATH)
    running = spent()
    say(f"Spent so far ${running:.4f} of ${cfg['budget_usd']:.2f}")
    for j in pending_jobs(jobs_doc, args.max_priority, args.job):
        est = estimate(cfg, j)
        ceiling = cfg["budget_usd"] if j["priority"] == 1 else cfg["budget_usd"] - cfg["reserve_usd"]
        fits = running + est <= ceiling
        say(f"  P{j['priority']} {j['id']:<26} {j['mode']:<8} {j['size']:<10} est ${est:.3f}  {'OK' if fits else 'WOULD STOP HERE'}")
        if not fits:
            break
        running += est
    say(f"Projected total if all above run: ${running:.4f}")


def cmd_run(cfg, args):
    global _secret
    if cfg["quality"] not in ("low", "medium"):
        sys.exit("Refusing to run: quality must be low (or medium for an owner-approved --job).")
    key = get_api_key()
    if not key:
        sys.exit("No API key found (OPENAI_API_KEY or ~/.trotro_rush/openai_api_key). Nothing generated.")
    _secret = key
    jobs_doc = load_json(JOBS_PATH)
    RAW_DIR.mkdir(exist_ok=True)
    made = 0
    for job in pending_jobs(jobs_doc, args.max_priority, args.job):
        refs = job.get("reference", [])
        refs = refs if isinstance(refs, list) else [refs]
        if job["mode"] == "edit" and not all((PROJECT / r).exists() for r in refs):
            say(f"STOP: {job['id']} needs its reference {job['reference']} (process earlier outputs first).")
            break
        est = estimate(cfg, job)
        room = allowance(cfg, job)
        if est > room:
            say(f"STOP: {job['id']} estimated ${est:.3f} but only ${max(room, 0):.3f} allowed. Budget protected.")
            break
        entries = ledger_entries()
        entry = {"time": time.strftime("%Y-%m-%d %H:%M:%S"), "job": job["id"], "mode": job["mode"],
                 "size": job["size"], "quality": cfg["quality"], "model": cfg["model"],
                 "estimated_usd": est, "actual_usd": 0.0, "status": "pending"}
        entries.append(entry)
        save_json(LEDGER_PATH, {"entries": entries})
        say(f"Generating {job['id']} (est ${est:.3f}, spent ${spent() - est:.4f} before this)...")
        try:
            result = call_api(cfg, job, key)
            usage = result.get("usage") or {}
            entry["usage_reported"] = bool(usage)
            entry["usage"] = {k: usage.get(k) for k in ("input_tokens", "output_tokens", "total_tokens")}
            entry["actual_usd"] = cost_from_usage(cfg, usage) if usage else est
            raw = RAW_DIR / f"{job['id']}.png"
            raw.write_bytes(base64.b64decode(result["data"][0]["b64_json"]))
            entry["raw"] = str(raw.relative_to(PROJECT))
            entry["status"] = "ok"
            made += 1
            say(f"  saved {entry['raw']}  cost ${entry['actual_usd']:.4f}")
        except urllib.error.HTTPError as e:
            detail = scrub(e.read().decode("utf-8", "replace"))[:400]
            entry["status"] = "http_error"
            entry["error"] = f"HTTP {e.code}: {detail}"
            say(f"  FAILED {entry['error']}")
            say("  Stopping; fix the cause before running again (failed requests are not billed).")
            entries[-1] = entry
            save_json(LEDGER_PATH, {"entries": entries})
            break
        except Exception as e:  # timeout / network: may or may not have been billed
            entry["status"] = "unknown"
            entry["error"] = scrub(repr(e))[:300]
            say(f"  UNKNOWN RESULT {entry['error']} (counted at estimate to stay safe)")
            entries[-1] = entry
            save_json(LEDGER_PATH, {"entries": entries})
            break
        entries[-1] = entry
        save_json(LEDGER_PATH, {"entries": entries})
    say(f"Done: {made} generated this run. Total spent ${spent():.4f} of ${cfg['budget_usd']:.2f}.")


def main():
    cfg = load_json(CONFIG_PATH)
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    for name in ("plan", "run"):
        p = sub.add_parser(name)
        p.add_argument("--max-priority", type=int, default=None)
        p.add_argument("--job", default=None)
        # Owner-approved exceptions only: raises quality for the --job named, never by default.
        p.add_argument("--quality", choices=["low", "medium"], default="low")
    args = ap.parse_args()
    if args.cmd in ("plan", "run") and args.quality != "low":
        if not args.job:
            sys.exit("--quality above low needs --job: it applies to one approved job at a time.")
        cfg = dict(cfg, quality=args.quality)
    {"status": cmd_status, "plan": cmd_plan, "run": cmd_run}[args.cmd](cfg, args)


if __name__ == "__main__":
    main()
