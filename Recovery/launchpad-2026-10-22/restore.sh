#!/bin/bash
set -euo pipefail
recovery_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$recovery_dir/../.." && pwd)"
case "${1:---check}" in
  --check) ;;
  --apply) ;;
  *) echo "Usage: bash restore.sh [--check|--apply]" >&2; exit 2 ;;
esac
cd "$project_dir"
/usr/bin/patch --dry-run --batch --forward -p1 < "$recovery_dir/restore.patch"
if [[ "${1:---check}" == "--apply" ]]; then
  /usr/bin/patch --batch --forward -p1 < "$recovery_dir/restore.patch"
  echo "Launchpad sources restored. Run swift test and ./script/build_and_run.sh --package."
else
  echo "Restore check passed; use --apply to restore the sources."
fi
