<!--
Stashed 2026-07-31 during the workspace retirement. This file is NOT referenced
from AGENTS.md and is not in docs/README.md, so it costs no session context. It
is kept so the pipeline can be re-integrated later rather than rewritten.
-->

> **Dormant.** The code-intelligence pipeline is not currently part of the
> working rules. The agent-facing rules that drove it are preserved at the end
> of this file. Re-integrate by moving those back into `AGENTS.md`.

# Code Intelligence Pipeline

This workspace uses the project-code-intelligence database as a Postgres-backed code
intelligence index for source navigation, feature work, bug hunting,
architecture exploration, patch comparison, and first-pass security review.
Direct source reads, builds, tests, and hardware evidence remain the source of
truth.

Postgres stores rebuildable code-intelligence state for this workspace.

## Design

The code intelligence index is layered:

- Repository snapshots: repo, role, branch, commit SHA, tree SHA, dirty state.
- Collections: a namespace for one workspace/product/team inside the same
  Postgres database, so unrelated repositories with the same short name do not
  collide.
- File inventory: path, git blob SHA, SHA-256, size, language, file role, and
  source/build/config/doc/test/vendor/generated classification.
- Records: syntax-oriented records such as code chunks, symbol definitions,
  config symbols, package definitions, patch hunks, DTS compatibles, service
  entry points, heuristic security candidates, and mirrored static-analysis
  findings.
- Edges: include edges and candidate call edges where the parser can infer
  relationships.
- Static analysis: SARIF runs, rules, findings, primary/related locations, and
  CodeQL-style code-flow steps are stored in first-class tables. Primary
  findings are also mirrored as `static_finding` records for normal text/vector
  retrieval.
- Optional embeddings: vector search is applied only to selected
  retrieval-oriented `embedding_text`, not blindly to every raw file.
- Incremental snapshots: after an initial scan, unchanged files are copied
  forward from the previous compatible snapshot with existing embeddings intact;
  only new or changed files are reparsed and re-embedded.

The first built-in producers are heuristic and stdlib-only:

- C/C++: include records, macro records, bounded function candidates, and call
  candidates.
- Rust and Go: bounded heuristic function/type chunks and call candidates.
- Python: stdlib AST function/class chunks, including class bodies and nested
  definitions.
- Make/Kconfig/DTS/patch/shell/resource/doc producers for build, config,
  firmware, and infrastructure-style repositories.
- Fallback line-window chunks when a parser cannot produce better structure.

Future producers should import proven formats instead of replacing this core:
SCIP for precise symbols/references, SARIF for Semgrep/CodeQL/static-analysis
findings, and Joern/code-property-graph exports for deeper security/data-flow.

Records carry a confidence label:

- `high_confidence_fact`: directly parsed from syntax or exact text.
- `approximate_fact`: useful fallback chunks or heuristic structure.
- `heuristic_candidate`: lead for investigation, not a confirmed bug.
- `tool_finding`: finding reported by an external static-analysis tool such as
  Semgrep or CodeQL. It is tool output, not independently confirmed proof.

Parser failures are stored in `project_code_intel_parser_failures` with the
snapshot, path, language, parser name, and error. These rows are operational
quality data: they show where the index degraded to fallback line windows.

## Normal Commands

Dry-run a repository relative to `--root`:

```sh
tools/project-code-intelligence/project-code-intelligence-ingest-code --root /path/to/workspace --repos my-repo --dry-run
```

For single-repo use, `--repos .` stores `source_path` as the repository-relative
path. For multi-repo collections, prefer named repo directories so source paths
remain visibly namespaced.

Profiles are additive extension points for project-specific metadata, security
eligibility, shell service records, Makefile typing, and `extra_records()`.
Changing profile output semantics requires bumping that profile's version so
incremental mode reparses affected records. The current implementation uses a
CLI-scoped `ACTIVE_PROFILE` global; if the ingester becomes a library or daemon,
pass the profile explicitly.

The MCP server is generic: use `code_intel_status` to inspect the current
collection, then query top-level fields and metadata. Exact profile-specific
metadata filters are available through `metadata_key`, `metadata_value`, and
JSON `metadata_contains`, for example
`{"luci_surface":["controller"]}`.

The ingester inventories tracked Git files. Add new files with `git add -N` or
stage them before refreshing when you want in-progress untracked files included
in the index.

Write structured records without embeddings. This is incremental by default:

```sh
PROJECT_CODE_INTELLIGENCE_ALLOW_WRITES=1 \
  tools/project-code-intelligence/project-code-intelligence-ingest-code \
  --collection mono-openwrt-project \
  --profile openwrt \
  --repos openwrt
```

Force a full reparse when parser versions, producer logic, or classifications
change:

```sh
PROJECT_CODE_INTELLIGENCE_ALLOW_WRITES=1 \
  tools/project-code-intelligence/project-code-intelligence-ingest-code \
  --collection mono-openwrt-project \
  --profile openwrt \
  --repos openwrt \
  --mode full
```

## Fresh Full Scan

Use this when starting from a stale or empty code-intelligence collection. Full
mode deletes previous code-intelligence snapshots for the selected repos in the
collection, then inserts a new snapshot. Test resets may also drop and recreate
the whole code-intelligence database/schema when that is simpler.

Set this environment block in the ingestion shell. The `openwrt` profile and
repo list select scoped SARIF discovery for `openwrt/codeql-results/**/*.sarif`
plus owned-repo SARIF files under `ask-cdx`, `ask-cmm`, and `fci`.

```sh
export PGVECTOR_HOST=192.168.14.9
export PGVECTOR_PORT=30432
export PGVECTOR_DB=code-intel
export PGVECTOR_USER=app
export PGVECTOR_PASS='<database-password>'

export PROJECT_CODE_INTELLIGENCE_REPOS=openwrt,ask-cdx,ask-cmm,fci
export PROJECT_CODE_INTELLIGENCE_COLLECTION=mono-openwrt-project
export PROJECT_CODE_INTELLIGENCE_PROFILE=openwrt
export PROJECT_CODE_INTELLIGENCE_MODE=full
export PROJECT_CODE_INTELLIGENCE_ALLOW_WRITES=1
export PROJECT_CODE_INTELLIGENCE_EMBED=1
export PROJECT_CODE_INTELLIGENCE_PREEMBED=0
export PROJECT_CODE_INTELLIGENCE_EMBEDDING_ENDPOINT=http://127.0.0.1:18081/v1/embeddings
export PROJECT_CODE_INTELLIGENCE_LLAMA_MODEL=$HOME/models/Qwen3-Embedding-8B-GGUF/Qwen3-Embedding-8B-Q8_0.gguf
```

Add `OpenWRT-ASK` to `PROJECT_CODE_INTELLIGENCE_REPOS` when the vendor reference tree
should be included in the scan; the SARIF defaults above already cover the
current scoped CodeQL output under `openwrt/codeql-results`.

For a clean code-intelligence schema reset before a test scan, add the explicit
reset flags:

```sh
PROJECT_CODE_INTELLIGENCE_ALLOW_WRITES=1 \
PROJECT_CODE_INTELLIGENCE_MODE=full \
  tools/project-code-intelligence/project-code-intelligence-refresh -- \
  --reset-code-intel --i-know-this-deletes-code-intel-db
```

The reset drops and recreates code-intelligence tables, including SARIF/static
analysis tables. It does not intentionally preserve prior code-intel snapshots.

Start the embedding server:

```sh
tools/project-code-intelligence/project-code-intelligence-embedding-server
```

Dry-run the full all-repo scan:

```sh
PROJECT_CODE_INTELLIGENCE_MODE=full \
  tools/project-code-intelligence/project-code-intelligence-refresh --dry-run
```

Run the full scan:

```sh
PROJECT_CODE_INTELLIGENCE_MODE=full \
  tools/project-code-intelligence/project-code-intelligence-refresh
```

After the full scan, use incremental updates after milestones:

```sh
PROJECT_CODE_INTELLIGENCE_MODE=incremental \
  tools/project-code-intelligence/project-code-intelligence-refresh
```

If embedding is interrupted after records are inserted, resume embeddings
without reparsing or rewriting records:

```sh
PROJECT_CODE_INTELLIGENCE_EMBED_ONLY=1 \
  tools/project-code-intelligence/project-code-intelligence-refresh
```

## Embedding Details

The Fresh Full Scan commands above enable semantic embeddings with
`PROJECT_CODE_INTELLIGENCE_EMBED=1`. Start a resident local embedding server before
those runs:

```sh
tools/project-code-intelligence/project-code-intelligence-embedding-server
```

The wrapper defaults to `llama-server` found on `PATH` and starts llama.cpp in
API embedding/listening mode on `http://127.0.0.1:18081/v1/embeddings`. If PATH
was just changed in `.bashrc`, source it or open a new shell before launching
the wrapper. It uses
`$HOME/models/Qwen3-Embedding-8B-GGUF/Qwen3-Embedding-8B-Q8_0.gguf` unless
`PROJECT_CODE_INTELLIGENCE_LLAMA_MODEL` is set. The current defaults are tuned for
unattended indexing on this machine with Qwen3-Embedding-8B Q8:

- `--ctx-size 40960`
- `--batch-size 2048`
- `--ubatch-size 1024`
- `--parallel 8`
- `--kv-unified`
- prompt cache and Web UI disabled
- llama.cpp default logging

The measured confirmation run with 4096 total context on the first 100 OpenWrt
files reached about `6.53` embeddings/second for the first 512 embedded
records, but longer runs showed llama.cpp context-limit errors with
`--parallel 8`. The default is now Qwen3-Embedding's 40960-token training
context so llama.cpp does not warn that `n_ctx_seq` is below `n_ctx_train`. A
2048-token total context failed on the same sample and should not be used for
full indexing.

If llama.cpp logs `Context size has been exceeded`, the input for one embedding
request tokenized beyond the context available to that server slot. The
`--ctx-size` value is not always available to a single request when the server
is handling multiple parallel slots, and character limits are only an estimate:
code, paths, macros, and punctuation can tokenize more densely than prose. The
ingester now handles this in stages:

- split a failed embedding batch into smaller batches;
- retry a single failed record with progressively smaller model input, down to
  `PROJECT_CODE_INTELLIGENCE_EMBEDDING_MIN_CHARS` default `800`;
- mark only the still-failing record as `embedding_skipped` so the overnight run
  continues.

To reduce or eliminate those server log messages, lower
`PROJECT_CODE_INTELLIGENCE_EMBEDDING_MAX_CHARS` to `1500` or `2000`, lower
`PROJECT_CODE_INTELLIGENCE_EMBEDDING_BATCH_SIZE`, reduce llama.cpp `--parallel`, or
increase `--ctx-size` if memory headroom allows it. These settings trade richer
per-record semantic text against fewer failed requests and less retry overhead.

The ingestion side caps the text sent to llama.cpp with
`PROJECT_CODE_INTELLIGENCE_EMBEDDING_MAX_CHARS` / `--embedding-max-chars`, default
`3000`. The full `embedding_text` remains stored in Postgres; only the model
input is shortened. `--embedding-max-chars` must be greater than zero; older
test versions treated `0` as "send full text", but that is now rejected because
it can recreate llama.cpp context failures. Omit `--embed` to disable
embeddings. If a batch still fails due to model context, the ingester splits
the batch and marks only a failing single record as
`embedding_skipped` instead of aborting the overnight run. Use the Fresh Full
Scan section for full, incremental, and embed-only resume commands.

When embeddings are enabled, code ingestion overlaps llama.cpp inference with
Postgres insertion/copy work. The background pre-embedding worker inserts ready
vectors with their records, but the ingester does not wait for it after the DB
upload window. Unfinished records are committed without vectors, then the
regular resumable post-insert embedding pass handles anything still missing.
Disable this with
`PROJECT_CODE_INTELLIGENCE_PREEMBED=0`; tune bounded lookahead with
`PROJECT_CODE_INTELLIGENCE_PREEMBED_AHEAD_BATCHES`, default `16`. For predictable
overnight runs with large embedding models, `PROJECT_CODE_INTELLIGENCE_PREEMBED=0` is
the simpler mode.

The code ingester emits `code_intel_runtime_heartbeat` on stderr every 300
seconds and a final `code_intel_runtime` event on normal exit or Ctrl-C. Set
`PROJECT_CODE_INTELLIGENCE_RUNTIME_HEARTBEAT_SECONDS` to adjust the interval, or `0`
to disable it. Heartbeat and final events include a `metrics` object with:

- timing buckets for scanning, Postgres upload/copy, embedding HTTP/CLI
  inference, embedding DB vector updates, and embedding preflight;
- record/file counters for changed, unchanged, generated, copied, embedded,
  skipped, retried, and context-error records;
- embedding input character counts and token counts;
- a `progress` object with `phase_percent` and
  `overall_percent_estimated`. Phase percentage is count-based; the overall
  value is deliberately labeled estimated because scan, DB upload, and
  embedding have different costs.

Token counts use the endpoint's reported `usage` fields when the local server
returns them. llama.cpp may omit that data; in that case the ingester records an
estimate using `ceil(chars/4)`. Override the estimate with
`PROJECT_CODE_INTELLIGENCE_TOKEN_CHARS_PER_TOKEN` if you calibrate it against a model
tokenizer. The estimate intentionally counts retries and failed requests because
those are real inference work and matter when comparing RAG ingestion cost with
non-RAG interactive token use.

## Static Analysis SARIF

SARIF ingestion is additive to source parsing. With
`PROJECT_CODE_INTELLIGENCE_PROFILE=openwrt`, profile discovery includes scoped
locations:

- `ask-cdx/**/*.sarif`, `ask-cdx/**/*.sarif.json`
- `ask-cmm/**/*.sarif`, `ask-cmm/**/*.sarif.json`
- `fci/**/*.sarif`, `fci/**/*.sarif.json`
- `openwrt/sarif/**`, `openwrt/semgrep-results/**`,
  `openwrt/codeql-results/**`, and `openwrt/reports/sarif/**`

The Fresh Full Scan defaults above select these profile globs, including recent
CodeQL output in `openwrt/codeql-results`. Use explicit SARIF paths or globs
for one-off imports:

```sh
PROJECT_CODE_INTELLIGENCE_COLLECTION=mono-openwrt-project \
PROJECT_CODE_INTELLIGENCE_PROFILE=openwrt \
  tools/project-code-intelligence/project-code-intelligence-refresh --dry-run -- \
  --sarif 'ask-cdx/results/*.sarif' \
  --sarif 'openwrt/codeql-results/*.sarif'
```

Use `--no-profile-sarif` when you want only explicitly listed SARIF files.
SARIF data is stored in:

- `project_code_intel_static_runs`
- `project_code_intel_static_rules`
- `project_code_intel_static_findings`
- `project_code_intel_static_locations`
- `project_code_intel_static_code_flows`

Each primary finding is mirrored into `project_code_intel_records` as
`record_type='static_finding'`, so existing text, metadata, and embedding
retrieval can find it.

SARIF `uriBaseId` values are resolved from run-level `originalUriBaseIds` when
present. Relative finding paths are only prefixed with a repo name when they
match an indexed source path or an existing file; unmatched analyzer paths stay
as reported so generated/build/dependency findings are not silently mis-mapped.

The MCP server also exposes first-class static-analysis tools:

- `search_static_findings`: exact-filter search over SARIF/static-analysis
  findings by collection, repo, tool, rule id, level, baseline state, or primary
  source path.
- `get_static_finding`: fetch one finding with its rule metadata, locations,
  and code-flow steps.
- `get_static_code_flow`: fetch ordered CodeQL/SARIF code-flow steps for one
  finding, optionally scoped to one flow index.

## Retrieval Rules

Use exact or lexical search first for symbols, paths, config names, packages,
error strings, APIs, and known filenames. Use semantic search for concepts and
similarity.

## Current Limits

The built-in parser is intentionally dependency-light and still heuristic. C,
Make, Kconfig, DTS, shell, Go, Rust, and Python records are useful for
navigation and search-space reduction, but they are not authoritative compiler
or language-server output. `call_candidate` edges and `security_pattern`
records should be treated as review leads, not proof of call relationships or
vulnerabilities. For higher-confidence code intelligence, supplement this store
with tree-sitter and/or universal-ctags output and keep direct source reads,
builds, tests, and static-analysis tools as source of truth.

Always expand selected candidates back to the current source tree before
editing. Code intelligence narrows the search space; it does not replace `rg`,
file reads, builds, tests, static-analysis tools, or hardware validation.


---

## Appendix: agent rules (dormant)

Preserved verbatim from the retired workspace `AGENTS.md`. These are **not
active** — they are here so the pipeline can be re-adopted without rewriting
them. The MCP server and the Postgres/pgvector database they assume were part
of the workspace setup, and `tools/project-code-intelligence/` was never
populated in the repo.

- Use `AGENTS.md`, `docs/project-map.md`, focused docs, and the current working
  tree for orientation before broad codebase exploration.
- The Postgres/pgvector database holds rebuildable code-intelligence state.
- Use the `project-code-intelligence` MCP server as the first pass for
  non-trivial codebase investigation, security review, branch comparison, or
  implementation touching unfamiliar code. Start with compact top-k searches,
  expand only selected records, then verify the chosen code paths against the
  working tree.
- Minimum expected code-intelligence first pass:
  - Run `code_intel_status` for the `mono-openwrt-project` collection.
  - Use `search_code_intel_text` for exact anchors such as paths, symbols,
    Kconfig names, package names, error strings, APIs, and CodeQL/Semgrep rule
    IDs.
  - Use `search_code_intel_semantic` for conceptual questions such as feature
    design, architecture exploration, similar code, policy behavior, and
    security review leads.
  - Use `search_static_findings`, `get_static_finding`, and
    `get_static_code_flow` for SARIF/CodeQL/Semgrep findings before reading
    generated reports directly.
  - Use `related_code_intel` to expand from a selected record to include
    edges, candidate calls, and same-symbol leads.
- In a progress update or final answer, include either
  `Code intelligence used: <queries/findings>` or
  `Code intelligence skipped: <specific reason>`. Skipping is acceptable only
  for purely mechanical tasks, exact file edits already identified by the user,
  or when the MCP is unavailable or clearly stale.
- Treat `call_candidate` edges as investigation hints until source/build
  evidence confirms them.
- Keep token use low by reading full files only after indexed search narrows
  the target. Prefer record IDs, summaries, metadata, and small source ranges
  over broad file dumps.
- Code intelligence for this workspace should use the `mono-openwrt-project`
  collection and the `openwrt` profile.
- Treat code-intelligence records as discovery leads, not final authority. If
  `code_intel_status` shows snapshots behind current refs, still use the MCP to
  find likely code paths, then verify all conclusions against live repository
  files, `git`, builds, tests, and hardware validation as appropriate.
- Refresh code intelligence with `tools/project-code-intelligence/project-code-intelligence-refresh`;
  set `PROJECT_CODE_INTELLIGENCE_COLLECTION=mono-openwrt-project` and
  `PROJECT_CODE_INTELLIGENCE_PROFILE=openwrt` for this workspace.
  Code refreshes are incremental by default and should reuse unchanged
  records/embeddings from the previous compatible snapshot unless a clean reset
  or full rescan is requested.
- At milestone closeout, remind the user to document durable decisions,
  validation results, package pins, or implementation state worth preserving.

**Note on `docs/project-map.md`**: the first rule above references it. That file
was dropped in the workspace retirement as superseded — its branch model and
SELinux sections had gone stale. Re-point that rule at `AGENTS.md`, `STATE.md`,
and `docs/README.md` if the pipeline is revived.
