#!/usr/bin/env bash
set -euo pipefail

# تابع نمایش استفاده صحیح
usage() {
  echo "Usage: $0 --api-url URL --token TOKEN"
  exit 1
}

# پارس کردن ورودی‌ها
API_URL=""
TOKEN=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --api-url) API_URL="$2"; shift 2 ;;
    --token)   TOKEN="$2";   shift 2 ;;
    *) usage ;;
  esac
done
[[ -z "$API_URL" || -z "$TOKEN" ]] && usage

# گرفتن لیست کاربران از XUI
users_json=$(curl -s -H "Authorization: Bearer $TOKEN" "$API_URL/users")

# استخراج Subscription IDها و گروه‌بندی کاربران
declare -A sub2users
mapfile -t subs < <(echo "$users_json" | jq -r '.data[].subscription_id' | sort | uniq)

for sub in "${subs[@]}"; do
  users=$(echo "$users_json" | jq -r --arg sub "$sub" '.data[] | select(.subscription_id==$sub) | .id')
  sub2users["$sub"]="$users"
done

# برای هر Subscription ID، بالاترین مصرف را تعیین و روی همه کاربران ست می‌کنیم
for sub in "${!sub2users[@]}"; do
  max_bw=0
  for uid in ${sub2users[$sub]}; do
    bw=$(echo "$users_json" | jq -r --arg id "$uid" '.data[] | select(.id==$id) | .used_bytes')
    (( bw > max_bw )) && max_bw=$bw
  done
  echo "Subscription $sub → تنظیم حداکثر حجم به $max_bw bytes روی کاربران:"
  for uid in ${sub2users[$sub]}; do
    echo " - کاربر $uid"
    curl -s -X PATCH \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"used_bytes\": $max_bw}" \
      "$API_URL/users/$uid" \
      | jq .
  done
done

echo "✔️ بروزرسانی مصرف برای تمام subscription ها انجام شد."
