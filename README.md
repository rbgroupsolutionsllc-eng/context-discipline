# 📉 Context Discipline & Token FinOps for AI Agents

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platforms: Linux | macOS](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS-lightgrey.svg)]()
[![Compatible with Claude Code, OpenCode, Codex, Antigravity](https://img.shields.io/badge/Agents-Claude%20%7C%20OpenCode%20%7C%20Codex%20%7C%20Antigravity-orange.svg)]()

> **Stop burning dollars on runaway context windows.**  
> A lightweight, zero-dependency forensic auditor and governance suite for CLI AI agents (**Claude Code**, **OpenCode**, **OpenAI Codex**, **Antigravity**, and **Cursor**).

---

## 💥 The Problem: Runaway Context Degradation

When working with CLI agents, small habits silently waste **millions of tokens** and degrade model IQ:
1. **Command Output Flooding:** Running `npm test`, `git log`, or `find` that prints 500+ lines straight into the context.
2. **Zombie Sessions:** Running a single thread for days (>800 turns), forcing every new prompt to re-read megabytes of stale logs.
3. **Running from `$HOME`:** Invoking an agent from `~` causes it to scan your entire drive, blowing past prompt cache boundaries.

---

## ⚡ Quick Start: 3-Second Forensic Audit

Scan your local agent environments with zero risk (**100% read-only**, touches no data):

```bash
git clone https://github.com/rbgroupsolutionsllc-eng/context-discipline.git
cd context-discipline
bash scripts/audit-context.sh
```

### Sample Output:
```text
================================================================
          CONTEXT DISCIPLINE & TOKEN FINOPS AUDIT               
================================================================
📦 CLAUDE CODE (Anthropic)
  Projects by footprint:
    142M   ~/.claude/projects/-home-user-projectA
    1.2G   ~/.claude/projects/-home-user-projectB
  Heaviest individual sessions:
    24M      912 turns   session-abc-123.jsonl
  [!] Bloated session: session-abc-123.jsonl (912 turns, 24M) — archive to restore speed

⚡ OPENCODE (SST / CLI)
  Database: 85M
  Top sessions by cached token read:
    .../my-app                           18.4 M tokens  $14.20     420 msgs

🛡️ CONTEXT DISCIPLINE GOVERNANCE
    [ACTIVE]   Claude Code (~/.claude/CLAUDE.md)
    [ACTIVE]   OpenCode (~/.config/opencode/AGENTS.md)
    [MISSING]  Codex (~/.codex/AGENTS.md)
```

---

## 🛡️ The 3 Golden Rules of Context Discipline

### Rule 1: Command Output Redirection
```bash
# ❌ NEVER DO THIS (Floods context with 500 lines):
pytest -v

# ✅ ALWAYS DO THIS (Caps context footprint to 1 line):
pytest -v > /tmp/test_run.txt; wc -l /tmp/test_run.txt
# Then inspect only what is needed:
grep -E "FAILED|ERROR" /tmp/test_run.txt
```

### Rule 2: One Task = One Clean Session
* Close or archive sessions when a task finishes.
* Record architecture state in `ESTADO.md` / `README.md` and start clean.

### Rule 3: Strict Project Scope
* Never run agents from `$HOME`. Always run from the project root directory.

---

## 🚀 1-Click Governance Deployment

Deploy the mandatory context discipline rules to your global agent configurations:

```bash
# Deploy to global configurations (~/.claude, ~/.config/opencode, ~/.codex):
bash scripts/inject-discipline-rules.sh global

# Or deploy to a specific repository workspace:
bash scripts/inject-discipline-rules.sh workspace /path/to/my-project
```

---

## 📂 Repository Structure

```text
context-discipline/
├── LICENSE                          # MIT License (RB Group Solutions LLC)
├── README.md                        # This Guide
├── SKILL.md                         # Portable Skill Definition
├── scripts/
│   ├── audit-context.sh             # Forensic CLI Scanner (Read-Only)
│   └── inject-discipline-rules.sh   # 1-Click Rules Deployer
└── references/
    ├── forensics.md                 # Deep JSONL & SQLite forensic analysis
    └── rules-deployment.md          # Multi-agent governance guide
```

---

## 📄 License
This project is open-source under the **[MIT License](LICENSE)**.  
Maintained with precision by **RB Group Solutions LLC**.
