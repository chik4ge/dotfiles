---
name: pyrunbox
description: Execute Python safely in disposable Docker sandboxes with pyrunbox, including package injection, network policy, and mount policy guidance.
---

## What I do

- I use `pyrunbox` for one-shot Python execution in a disposable container.
- Secure defaults help reduce risk: no network unless requested, reduced container privileges, and limited resources.
- `--with` is useful for ad-hoc packages without `requirements.txt`.
- Least-privilege mounts keep intent clear (`--mount` for read-only, `--mount-rw` for intentional writes).
- Python runtime can be selected with `--python 3.12|3.13|3.14` (default `3.14`).
- Prefer direct heredoc (`pyrunbox <<'PY'`) for multi-line scripts; keep examples concise and copy-paste friendly.

## Current command behavior

- Base image is mapped internally from `--python` to `ghcr.io/astral-sh/uv:python<ver>-bookworm`.
- `--network` uses Docker host networking.
- Without `--network`, runtime stays isolated (`--network none`).
- If `--with` is used without `--network`, dependencies are prefetched first and execution runs offline.
- On network-enabled runs, `SSL_CERT_FILE` and `REQUESTS_CA_BUNDLE` are set to system CA path by default.
- Extra mounts:
  - `--mount src:dst` => read-only bind
  - `--mount-rw src:dst` => read-write bind

## Recommended usage patterns

```bash
# Tiny sanity check
pyrunbox -c "import sys; print(sys.version.split()[0])"

# Multi-line example
pyrunbox <<'PY'
from collections import Counter

items = ["api", "api", "worker", "db"]
print(Counter(items))
PY

# Package injection without runtime network access
pyrunbox --with requests <<'PY'
import requests
print(requests.__version__)
PY

# Enable network only when external access is required
pyrunbox --network --with requests <<'PY'
import requests
r = requests.get('https://example.com', timeout=10)
print(r.status_code, len(r.text))
PY

# Pin Python version when behavior depends on runtime
pyrunbox --python 3.13 <<'PY'
import sys
print(sys.version)
PY

# Read-only input mount
pyrunbox --mount ./input.json:/data/input.json <<'PY'
import json
print(json.load(open('/data/input.json')))
PY

# Intentional write with read-write mount
pyrunbox --mount-rw ./out.txt:/data/out.txt <<'PY'
from datetime import datetime, timezone
open('/data/out.txt', 'w').write(datetime.now(timezone.utc).isoformat() + '\n')
PY
```

## Safety checklist

- Use `-c` only for one-liners (single expression).
- `--network` is usually unnecessary unless internet/LAN access is required.
- `--mount` (ro) fits read-only access, while `--mount-rw` fits intentional writes.
- Minimal and pinned injected packages improve reproducibility.
- Explicit `--python` helps when scripts are sensitive to minor-version behavior.
