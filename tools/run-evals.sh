#!/usr/bin/env bash
# Run the eval suites under evals/<plugin>/ with `claude plugin eval` (Claude Code >= 2.1.269).
# Costs API credits: every run is a full Claude session.
#
# Usage:   bash tools/run-evals.sh                 # triggers + negatives, 1 run, no baseline (quick routing check)
#          bash tools/run-evals.sh behaviour       # behaviour cases, 3 runs, with/without-plugin baseline
#          bash tools/run-evals.sh agents          # agent cases: builds a small project fixture, delegates, 1 run
#          bash tools/run-evals.sh all [extra flags passed to claude plugin eval]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-routing}"; shift || true

common=(--eval-dir evals --trust-plugin --no-publish -j "${EVAL_CONCURRENCY:-4}" --max-cost-usd "${EVAL_MAX_COST_USD:-30}")
cd "$ROOT"
case "$mode" in
  routing)   exec claude plugin eval . "${common[@]}" --tag trigger negative --runs 1 --ablation none "$@" ;;
  behaviour) exec claude plugin eval . "${common[@]}" --tag behaviour --runs 3 "$@" ;;
  agents)    exec claude plugin eval . "${common[@]}" --tag agent --runs 1 --ablation none --scaffold --allow-tools Agent "$@" ;;
  all)       exec claude plugin eval . "${common[@]}" "$@" ;;
  *)         echo "usage: $0 [routing|behaviour|agents|all] [claude plugin eval flags]" >&2; exit 2 ;;
esac
