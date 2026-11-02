#!/bin/bash
set -euo pipefail
backup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$backup_dir/../.." && pwd)"
case "${1:---check}" in
    --check|--apply) ;;
    *) echo "Usage: bash restore.sh [--check|--apply]" >&2; exit 2 ;;
esac
cd "$project_dir"
patch --dry-run --batch --forward -E -p1 < "$backup_dir/restore.patch"
if [[ "${1:---check}" == "--apply" ]]; then
    patch --batch --forward -E -p1 < "$backup_dir/restore.patch"
    echo "Previous sources restored. Rebuild both apps before installing."
fi
