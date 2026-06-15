#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
jq -r '.[] | [.id, .family, .distro, .version] | @tsv' "$PROJECT_ROOT/config/targets.json"
