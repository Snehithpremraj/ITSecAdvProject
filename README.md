# LLM Exploit Chain Lab

An academic security-research project that demonstrates — and then mitigates — a
four-link attack chain against an LLM-based assistant. The target is a mock
**Acme Corp HR/IT Assistant** built on `llama3.2:3b` (served locally by
[Ollama](https://ollama.com/)), wrapped in a FastAPI chat interface.

> **Scope & ethics.** This is a self-contained lab for studying LLM
> vulnerabilities and defenses. Everything runs against a local model and a
> throwaway SQLite database on your own machine. The most dangerous surface
> (Link 4, shell execution) is disabled by default and only ever arms inside a
> container. Do not point any of this at systems you don't own or aren't
> authorized to test.

---

## The attack chain

The project walks a realistic escalation from a single jailbreak to persistent
compromise and, finally, code execution:

| Link | Attack | CWE | Result |
|------|--------|-----|--------|
| **1** | Prompt injection / jailbreak | CWE-94 | Leak `PRODUCT_KEY` from the system prompt |
| **2** | Broken function-level authorization (BFLA) | CWE-863, CWE-20 | Overwrite the system prompt via `update_config` |
| **3** | Persistent prompt injection | CWE-20 | Seeded instruction fires in later, unrelated victim sessions |
| **4** | Remote code execution | CWE-78 | Shell exec via an opaque seed token — `uid=0(root)` |

A key research finding is that payload **shape** decides reliability on a small
(3B) model: the same seed instruction fails when it carries a bare command but
succeeds when the command is hex-encoded inside an opaque `SEEDCH4-<hex>` token
that the model relays verbatim. See the write-ups below for the full narrative.

### Documentation

- **`PROJECT_REPORT.md`** — the comprehensive report: every link, dead ends,
  mitigations, and findings.
- **`FINDINGS_link4_redesign.md`** — the Link 4 RCE redesign and measured
  results.
- **`PAYLOADS_RUNBOOK.md`** — payloads and how to reproduce each step.
- **`bfla_ch2/FINDINGS_link2_key_recall.md`** — the small-model
  credential-placeholder finding.

---

## Repository layout

```
.
├── frontend/               # FastAPI chat UI + researcher inspection view
│   ├── main.py             #   app entrypoint (uvicorn frontend.main:app)
│   └── static/index.html   #   attacker-facing chat page
├── prompt_inj_ch1/         # Link 1: harness, model tools, DB setup, exploit
│   └── setup_db.py         #   builds acme.db from scratch
├── bfla_ch2/               # Link 2: update_config tool (BFLA)
├── assistant_comp_ch3/     # Link 3: notify tool + persistent seed payload
│                           #   (also holds the Docker-gated Link 4 notify swap)
├── mitigations/            # Structural fixes (secure config tool + templated prompt)
├── full_chain_exploit.py   # Drives the whole chain end-to-end
├── mitigated_chain_exploit.py  # Same chain against the mitigated build
├── Dockerfile              # Container image for the lab
├── docker-compose.yml      # Base service (Link 4 disabled)
├── docker-compose.link4.yml# Overlay that ARMS Link 4 (CWE-78) — container only
└── requirements.txt
```

---

## Prerequisites

- **Python 3.12** (the project is developed against 3.12.3).
- **[Ollama](https://ollama.com/)** running locally, with the target model
  pulled:
  ```bash
  ollama pull llama3.2:3b
  ```
  Make sure the Ollama server is up (`ollama serve`, or the desktop app) and
  reachable at its default `http://localhost:11434`.
- **Docker + Docker Compose** — only if you want the containerized run.

---

## Running locally (native)

This is the simplest way to bring up the chat lab.

```bash
# 1. Clone and enter the repo
git clone <your-repo-url> it_sec_proj
cd it_sec_proj

# 2. Create a virtualenv and install dependencies
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 3. Build the throwaway SQLite database (run once)
python prompt_inj_ch1/setup_db.py

# 4. Start the server
uvicorn frontend.main:app --host 0.0.0.0 --port 8000
```

Then open **http://localhost:8000** in a browser to reach the assistant chat
UI. A read-only **researcher view** of server-side tool activity (SQL executed,
tool results, model prose) is available at **http://localhost:8000/inspect**,
and a health check at **http://localhost:8000/health**.

> Ollama runs *outside* the app as a separate process. If your Ollama server
> isn't on the default host/port, set `OLLAMA_HOST` before launching uvicorn.

### Optional environment variables

The app defaults these to sensible paths inside `prompt_inj_ch1/`, but you can
override them:

| Variable | Purpose | Default |
|----------|---------|---------|
| `OLLAMA_HOST` | Where to reach the Ollama server | `http://localhost:11434` |
| `ACME_DB_PATH` | SQLite database path | `prompt_inj_ch1/acme.db` |
| `ACME_TOOL_LOG` | Tool-call log (JSONL) | `prompt_inj_ch1/tool_calls.jsonl` |
| `ACME_NOTIFY_LOG` | Notify-call log (JSONL) | `prompt_inj_ch1/notify_calls.jsonl` |
| `ACME_LINK4_RCE` | Arms the dangerous `notify` swap (CWE-78). **Container only.** | unset (Link 4 disabled) |

---

## Running with Docker

The container builds the database on startup (via `entrypoint.sh`) and serves
the app on port 8000. Ollama still runs on the host; the compose file wires
`host.docker.internal` so the container can reach it.

```bash
# Base run — Link 4 stays DISABLED
docker-compose up --build
```

Open **http://localhost:8000** as before.

### Arming Link 4 (RCE) — sandboxed only

Link 4 executes shell commands the model was seeded with. It is opt-in and
should **only** be enabled inside the container, by layering the overlay
compose file (which sets `ACME_LINK4_RCE=1`):

```bash
docker-compose -f docker-compose.yml -f docker-compose.link4.yml up --build
```

> **Never** set `ACME_LINK4_RCE=1` on your host. That environment variable is
> the seam that turns a seeded tool call into arbitrary command execution.

---

## Reproducing the exploit chain

With the model and (for Link 4) the armed container running, the end-to-end
driver replays the full chain and writes artifacts under `chain_exploit_runs/`:

```bash
python full_chain_exploit.py
```

To measure Link 4 reliability specifically:

```bash
python full_chain_exploit.py --measure-link4 40
```

To confirm the defenses hold, run the same chain against the mitigated build:

```bash
python mitigated_chain_exploit.py
```

See `PAYLOADS_RUNBOOK.md` for step-by-step payloads and expected output for
each link.

---

## Mitigations

The `mitigations/` directory implements the structural (not instructional)
defenses discussed in `PROJECT_REPORT.md`:

- **`config_tool_secure.py`** — authorization captured at tool-registration
  time from real auth state (fixes CWE-863); the free-text `new_system_prompt`
  parameter is removed in favor of a short, regex-validated topic list (fixes
  CWE-20).
- **`secure_prompt.py`** — the system prompt is rendered from a fixed template
  plus validated data fields, so config data can never reach the prompt as
  executable instructions (closes the persistence surface from Link 3).

Against these, Link 1's jailbreak still leaks embedded context, but Links 2–4
are blocked: there is no credential argument to abuse and config writes never
become instructions.

---

## Notes

- Generated artifacts — `acme.db`, `*.jsonl` run logs — are git-ignored and
  rebuilt from `setup_db.py`. Logs can contain leaked secrets, so they are kept
  out of version control by design.
- In-memory session state dies on server restart. That's intentional for a
  demo; it is not a production pattern.
- This lab exists for education and defensive research. Treat every payload and
  finding accordingly.
