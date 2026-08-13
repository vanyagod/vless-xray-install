#!/usr/bin/env bash
# VLESS Xray installer (TCP, no TLS) — port 8309
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/install.sh)

set -euo pipefail

PORT="${PORT:-8309}"
TAG="${TAG:-vless}"
CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="${CONFIG_DIR}/config.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[+]${NC} $*"; }
fail()  { echo -e "${RED}[!]${NC} $*"; exit 1; }

if [[ "$(id -u)" -ne 0 ]]; then
  fail "Запусти от root: sudo bash install.sh"
fi

info "Установка Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

command -v xray >/dev/null 2>&1 || fail "Xray не установлен"

UUID="$(xray uuid)"
ok "UUID: ${UUID}"

info "Определение публичного IP..."
IP=""
for url in \
  "https://api.ipify.org" \
  "https://ifconfig.me/ip" \
  "https://icanhazip.com"
do
  IP="$(curl -4 -fsSL --max-time 8 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ -n "$IP" ]]; then
    break
  fi
done

if [[ -z "$IP" ]]; then
  IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi

[[ -n "$IP" ]] || fail "Не удалось определить IP. Задай вручную: IP=x.x.x.x bash install.sh"
ok "IP: ${IP}"

mkdir -p "$CONFIG_DIR"

info "Пишем конфиг ${CONFIG_FILE}..."
cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

info "Открываем порт ${PORT}/tcp (если есть firewall)..."
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then
  ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
fi

# iptables fallback (best-effort)
if command -v iptables >/dev/null 2>&1; then
  iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null \
    || iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || true
fi

systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray
sleep 1

if ! systemctl is-active --quiet xray; then
  journalctl -u xray -n 30 --no-pager || true
  fail "Xray не запустился"
fi
ok "Xray запущен на порту ${PORT}"

LINK="vless://${UUID}@${IP}:${PORT}?encryption=none&security=none&type=tcp&headerType=none#${TAG}"

echo
echo "=========================================="
echo -e "${GREEN}Готово. Твоя ссылка:${NC}"
echo
echo "$LINK"
echo
echo "=========================================="
echo
echo "Сохранено также в: /root/vless-link.txt"
echo "$LINK" > /root/vless-link.txt
