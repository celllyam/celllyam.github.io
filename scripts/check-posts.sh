#!/usr/bin/env bash
# 공개 전 점검 스크립트
#  - 로컬(pre-commit 훅): 민감어 목록(.sensitive-terms) + 패턴 검사
#  - CI(--ci): 민감어 목록은 없으므로 패턴 + 업무회고 sanitized 플래그만 검사
#
# 사용법:
#   bash scripts/check-posts.sh          # 로컬 전체 검사
#   bash scripts/check-posts.sh --ci     # CI 모드
set -euo pipefail

MODE="${1:-local}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POSTS_DIR="$ROOT/content"
TERMS_FILE="$ROOT/.sensitive-terms"
fail=0

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }

# 공개 저장소에서는 draft: true 글도 git 이력으로 누구나 읽을 수 있다.
# 그래서 draft 여부와 무관하게 커밋 대상 .md 전부를 검사한다.
# (작업 중인 초안은 *.wip.md 로 저장 — .gitignore와 hugo ignoreFiles 양쪽에서 제외됨)
mapfile -t published < <(find "$POSTS_DIR" -type f -name '*.md' ! -name '*.wip.md' | sort)

if [[ ${#published[@]} -eq 0 ]]; then
  echo "검사할 글 없음 — 통과"
  exit 0
fi

for f in "${published[@]}"; do
  rel="${f#"$ROOT"/}"

  # 1) 업무회고는 sanitized: true 필수 (초안 상태로 커밋하는 것 자체를 금지)
  if grep -qE '^categories:.*업무회고' "$f"; then
    if ! grep -qE '^sanitized:[[:space:]]*true' "$f"; then
      red "[차단] $rel — 업무회고인데 sanitized: true 가 아님"
      fail=1
    fi
    if grep -qE '^- \[ \]' "$f"; then
      red "[차단] $rel — 공개 전 점검 체크리스트에 미체크 항목이 있음"
      fail=1
    fi
  fi

  # 2) 사설 IP 대역 (192.168.100.x 랩 대역은 허용)
  # 줄 단위가 아니라 IP 단위로 추출해서 걸러야, 랩 IP와 같은 줄에 있는 사내 IP를 놓치지 않음
  if grep -oE '\b(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.[0-9]{1,3}\.[0-9]{1,3}\b' "$f" \
       | grep -vE '^192\.168\.100\.[0-9]{1,3}$' ; then
    red "[차단] $rel — 랩 대역(192.168.100.0/24) 외의 사설 IP가 있음"
    fail=1
  fi

  # 3) 사내 도메인/호스트명 흔적
  if grep -niE '\.(corp|internal|intranet|local)\b' "$f" | grep -viE 'svc\.cluster\.local'; then
    ylw "[경고] $rel — 사내 도메인으로 보이는 문자열이 있음. 확인 필요"
  fi

  # 4) 이메일 주소
  if grep -nE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" | grep -viE 'git@github\.com|example\.(com|org)'; then
    ylw "[경고] $rel — 이메일 주소가 있음. 확인 필요"
  fi

  # 5) 티켓/변경 번호 형태 (예: CHG1234567, INC0012345, ABC-1234)
  if grep -nE '\b(CHG|INC|RITM|PRB|CR|SR)[0-9]{5,}\b|\b[A-Z]{2,10}-[0-9]{3,}\b' "$f"; then
    ylw "[경고] $rel — 티켓 번호로 보이는 문자열이 있음. 확인 필요"
  fi

  # 6) 비밀값 흔적
  if grep -nE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|(password|passwd|secret|token)[[:space:]]*[:=][[:space:]]*[^[:space:]<]{6,}' "$f"; then
    red "[차단] $rel — 비밀값으로 보이는 문자열이 있음"
    fail=1
  fi

  # 7) 개인 민감어 목록 (로컬 전용, 저장소에 커밋하지 않음)
  if [[ "$MODE" != "--ci" && -f "$TERMS_FILE" ]]; then
    while IFS= read -r term; do
      [[ -z "$term" || "$term" == \#* ]] && continue
      if grep -niF -- "$term" "$f" >/dev/null; then
        red "[차단] $rel — 민감어 목록의 단어 포함: (목록 ${TERMS_FILE##*/} 참조)"
        fail=1
        break
      fi
    done < "$TERMS_FILE"
  fi
done

if [[ "$MODE" != "--ci" && ! -f "$TERMS_FILE" ]]; then
  ylw "[안내] .sensitive-terms 파일이 없습니다. 회사명·시스템명 등을 한 줄에 하나씩 적어두세요."
fi

if [[ $fail -ne 0 ]]; then
  red "공개 점검 실패 — 위 항목을 수정하거나 draft: true 로 되돌리세요."
  exit 1
fi
echo "공개 점검 통과 (${#published[@]}개 글)"
