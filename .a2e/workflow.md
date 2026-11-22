# Agent-neutral a2e workflow and roles

Choose the light tier for isolated changes; it does not require the full gate path. For boundary, security, or multi-repository changes use Tier 2. In a host without a configured edit guard, this is a human-managed workflow: do not claim a caged or enforced run. The human must manage scope, frozen tests and all verification.

For Tier 2 use `a2e_entry.run_dir(root)` (add `.a2e/scripts` to Python's module search path) to identify `.a2e/runs/<safe-branch-id>/` and copy `.a2e/_specs/spec-template.md` to its `spec.md`. Complete the spec. Before starting and whenever the spec or branch changes, the coordinator requires a successful current `python3 .a2e/scripts/a2e_entry.py --root <git-root>` result; failure blocks entry. The validator checks structure and placeholders, not substantive approval. Human gate 1 approves the spec and freezes tests before activating any available cage. Recommend 1–2 builders; each must receive the current successful validator result. Escalate contradictions to the human.

## Builder

Before starting, require the coordinator's successful current validator result for the present branch and spec; stop if missing or stale. This is a coordination requirement, not automatic runtime enforcement. Implement only the approved spec and permitted primary-repository paths. Do not edit tests, manifests, cage controls, enforcement configuration, or siblings. No shell, installations, or external operations. If blocked or the specification conflicts with the tests, stop and report the conflict to the human owner. The owner runs explicitly selected checks.

## Auditor

Review the approved invariants and manifest-listed evidence only. Identify evidence gaps, impacts, pending human dispositions, and recommended fixes. Do not run commands, modify files, develop exploits, or perform active probing. Return findings and exact evidence references to the workflow owner; the owner writes the report. Do not assert a pass from missing or failed evidence. Suggest two or three defensive, change-specific comprehension questions about affected boundaries, invariants, and evidence limitations for the human owner. Identify each required finding and its evidence; only the human may answer, confirm spec synchronization, or provide a reasoned snapshot-and-finding-scoped waiver. Do not claim a signature or independently unlock Gate 3.

## Evidence and human review

The owner explicitly chooses verification commands, collects evidence, and asks the read-only auditor to review it. Human gate 3 reviews gaps, findings, and evidence and decides whether to proceed. Never infer approval from green checks. Compare approved diagrams with manifest-listed Git summaries and actual source; label unobserved relationships unknown. Inspect explicitly listed repository evidence and contracts for possible consumers and unknown compatibility. Sibling inventory is not proof of consumer analysis. Do not modify siblings or run sibling checks. Review checksums and gaps; cite only manifest-listed artifacts and warn before sharing logs.

The Claude edit hook guards configured edit tools when active; it is not a sandbox, and `--add-dir` visibility does not isolate writes. Other hosts receive no runtime guard from generic instructions. See the installation guide for commands and limitations.

## Readable evidence runs

For the experimental linked workflow, run `python3 .a2e/scripts/a2e_run.py --root . --id NAME init` from the target Git root. Both installed adapters provide it. The starter creates only `.a2e/specs/NAME.feature`, `.a2e/packets/NAME.json` and `.a2e/tests/NAME.py`; the scaffold deliberately fails until replaced with real assertions. Author tagged Gherkin scenarios as the human contract, declare components and directed connections, and link their IDs and scenario IDs to executable native checks in the v2 packet. This is not translation, discovery, architecture verification, or a sandbox; runners may reference existing project tests and execute with the owner's permissions.

Review the packet and runners, then use `plan --base BASE --packet .a2e/packets/NAME.json`, `preflight`, `approve --packet-sha256 DIGEST`, `baseline`, `candidate`, and `status` or `draft`, each with the same `--root` and `--id` before the subcommand. Plan prints the approval digest; baseline requires a clean tree at the pinned base and ignored `.a2e/runs/`. Runners write `result.json` and any private artifacts under `A2E_OUTPUT_DIR`. Changed feature, packet or runner invalidates approval/evidence; create a new plan with a new ID. Reports show declared links and missing/stale evidence, not proof of coverage or truth. Legacy packets are explicitly unlinked. For syntax and details see the source documentation `docs/evidence-run.md` when available.

## Initialize collectors

Ask the owner which boundaries, local base, checks and exact commands they want. Inspect project files only as suggestions: never execute discovered commands, install packages, access the network, or infer approval from a manifest. Present each exact command and its effects for explicit owner selection before creating or running a collector. Do not put credentials in config or logs. Explain that checks execute with the owner's privileges and environment, and that unconfigured tools are not verified.

Copy `.a2e/evidence.example.yaml` to `.a2e/evidence.yaml` after review. It is JSON (a YAML subset); configure root-relative patterns and reviewed repository-local scripts. Create scripts only for explicitly selected commands, and pass matched paths as literal arguments where the chosen tool supports them. Review quoting, tool-specific options and side effects with the owner; do not construct shell commands from paths. The owner invokes `.a2e/collectors/run-diff.sh --help` and chooses a local base, phase and whether to use `--execute`. Report missing coverage as a gap or not configured.

## Human-attested offline Gate 3 preview

Prepare a private findings JSON array, for example `[{"id":"A1","required":true,"status":"open","description":"missing boundary evidence"}]`; status is `open` or `resolved`. Explicitly supply `[]` if there are no findings. The human is responsible for a complete and accurate findings list; the CLI cannot discover omitted findings. Run `python3 .a2e/scripts/a2e_signoff.py --root ROOT --base BASE --manifest AFTER_MANIFEST --findings FINDINGS_JSON` for the checklist. Pass the same `--config`, `--annotations`, and `--siblings` inputs used for review if applicable. No collectors or network operations run here. The spec and current evidence must validate; changes to spec, report, evidence, or findings change snapshot identity.

A human reviews the spec, evidence, findings and checklist questions. Create a private JSON attestation outside changed source paths, e.g. in the current run directory:

```json
{"snapshot_sha256":"CHECKLIST_DIGEST","human":"reviewer name","spec_sync_confirmed":true,"answers":["answer to question 1","answer to question 2"],"waivers":[{"snapshot_sha256":"CHECKLIST_DIGEST","finding_id":"EXACT_FINDING_ID","reason":"specific reason and accepted risk"}]}
```

Use an empty waiver list when no findings need waivers. Never invent human answers or waivers. Re-run with `--attestation PATH` for a local Markdown preview; recompute the checklist after any change. Old attestations and waivers do not carry forward. Add `--record` to emit a private JSON Decision & Evidence Record; do not publish it by default. A human attestation is not a signature or proof of comprehension. The public-safe preview excludes A3 references and assets, local paths, source lines and raw logs. Add approved durable URLs only by a separate human manual edit and review. Publish manually if desired; no upload, GitHub call, commit or cage removal is performed.
