#!/usr/bin/env bash
# 커밋할 때마다 check-posts.sh 를 자동 실행하는 git pre-commit 훅 설치
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cat > "$ROOT/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
exec bash "$(git rev-parse --show-toplevel)/scripts/check-posts.sh"
HOOK
chmod +x "$ROOT/.git/hooks/pre-commit"
echo "pre-commit 훅 설치 완료"
