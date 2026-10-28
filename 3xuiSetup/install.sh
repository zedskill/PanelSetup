#!/usr/bin/env bash
# 3xuiSetup — official MHSanaei 3x-ui + inbound set + optional DOMAIN HTTPS
set -euo pipefail
DOMAIN="${DOMAIN:-${CUSTOM_DOMAIN:-}}"
SCRIPT_URL="https://raw.githubusercontent.com/MHSanaei/3x-ui/main/install.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
SEED_URL="${SEED_URL:-https://raw.githubusercontent.com/zedskill/PanelSetup/main/3xuiSetup/seed_inbounds.py}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ca-certificates tar tzdata socat openssl cron nginx libnginx-mod-stream certbot python3 >/dev/null || true

curl -fsSL "$SCRIPT_URL" -o /tmp/3x-ui-official.sh
chmod +x /tmp/3x-ui-official.sh

export XUI_NONINTERACTIVE=1
export XUI_DB_TYPE="${XUI_DB_TYPE:-sqlite}"
bash /tmp/3x-ui-official.sh

IP=$(hostname -I | awk '{print $1}')
if [ -n "$DOMAIN" ]; then
  export DOMAIN R443=10444
else
  unset R443 || true
fi
SEED="$HERE/seed_inbounds.py"
if [ ! -f "$SEED" ]; then
  curl -fsSL "$SEED_URL" -o /tmp/3xui-seed_inbounds.py
  SEED=/tmp/3xui-seed_inbounds.py
fi
python3 "$SEED"

PANEL_PORT=2053
WEB_PATH=""
if [ -f /etc/x-ui/install-result.env ]; then
  # shellcheck disable=SC1091
  set -a
  # values are shell-escaped
  . /etc/x-ui/install-result.env
  set +a
  PANEL_PORT="${XUI_PANEL_PORT:-$PANEL_PORT}"
  WEB_PATH="${XUI_WEB_BASE_PATH:-}"
  WEB_PATH="${WEB_PATH#/}"
  WEB_PATH="${WEB_PATH%/}"
fi

mkdir -p /var/www/acme /etc/nginx/stream.d
CERT="/etc/letsencrypt/live/${DOMAIN:-x}/fullchain.pem"
KEY="/etc/letsencrypt/live/${DOMAIN:-x}/privkey.pem"

write_http_only() {
  cat > /etc/nginx/sites-available/3xui << NGEOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    location /.well-known/acme-challenge/ { root /var/www/acme; }
    location / { return 301 http://\$host:3169\$request_uri; }
}
server {
    listen 3169 default_server;
    listen [::]:3169 default_server;
    client_max_body_size 32m;
    location / {
        proxy_pass http://127.0.0.1:${PANEL_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600s;
    }
}
NGEOF
}

if [ -n "$DOMAIN" ]; then
  write_http_only
  ln -sfn /etc/nginx/sites-available/3xui /etc/nginx/sites-enabled/3xui
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl enable --now nginx && systemctl reload nginx
  if [ ! -f "$CERT" ]; then
    certbot certonly --webroot -w /var/www/acme -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email || true
  fi
  if [ -f "$CERT" ]; then
    python3 - << 'PY'
from pathlib import Path
p = Path("/etc/nginx/nginx.conf")
t = p.read_text()
if "include /etc/nginx/stream.d/" not in t:
    p.write_text(t.rstrip() + "\n\nstream {\n    include /etc/nginx/stream.d/*.conf;\n}\n")
PY
    cat > /etc/nginx/sites-available/3xui << NGEOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/acme; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 127.0.0.1:10443 ssl http2;
    listen 3169 ssl http2 default_server;
    listen [::]:3169 ssl http2 default_server;
    server_name ${DOMAIN};
    ssl_certificate ${CERT};
    ssl_certificate_key ${KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 32m;
    location / {
        proxy_pass http://127.0.0.1:${PANEL_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 3600s;
    }
}
NGEOF
    cat > /etc/nginx/stream.d/3xui-sni.conf << SNEOF
map \$ssl_preread_server_name \$xui_sni_upstream {
    ${DOMAIN} 127.0.0.1:10443;
    default 127.0.0.1:10444;
}
server {
    listen 443;
    listen [::]:443;
    ssl_preread on;
    proxy_pass \$xui_sni_upstream;
    proxy_connect_timeout 5s;
}
SNEOF
  fi
else
  write_http_only
fi

ln -sfn /etc/nginx/sites-available/3xui /etc/nginx/sites-enabled/3xui
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl enable --now nginx && systemctl reload nginx || true

for p in 80 443 3169 5000 5001 5002 5003 8443 8444 10444; do
  iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$p" -j ACCEPT
done
iptables -C INPUT -p udp --dport 5003 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 5003 -j ACCEPT

mkdir -p /root
if [ -f /etc/x-ui/install-result.env ]; then
  cp -a /etc/x-ui/install-result.env /root/3xui-credentials.txt
  chmod 600 /root/3xui-credentials.txt
fi
RPORT=443
[ -n "$DOMAIN" ] && RPORT=10444
if [ -n "$DOMAIN" ] && [ -f "$CERT" ]; then
  PANEL_URL="https://${DOMAIN}/${WEB_PATH:+$WEB_PATH/}"
else
  PANEL_URL="http://${IP}:3169/${WEB_PATH:+$WEB_PATH/}"
fi
{
  echo "3x-ui"
  echo "Panel: ${PANEL_URL}"
  echo "IP: $IP"
  echo "Credentials: /root/3xui-credentials.txt"
  echo "CLI: x-ui"
  echo "VLESS TCP REALITY ${IP}:${RPORT}"
  echo "VLESS gRPC REALITY ${IP}:8443"
  echo "VLESS XHTTP REALITY ${IP}:8444"
  echo "VLESS TCP ${IP}:5000"
  echo "VMess TCP ${IP}:5001"
  echo "Trojan TCP ${IP}:5002"
  echo "Shadowsocks ${IP}:5003"
} | tee -a /root/3xui-credentials.txt >/dev/null

echo "============================="
echo "3x-ui installed"
echo "Panel: ${PANEL_URL}"
echo "Credentials: /root/3xui-credentials.txt"
echo "============================="
