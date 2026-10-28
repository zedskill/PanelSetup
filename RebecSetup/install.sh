#!/usr/bin/env bash
# RebecSetup — official Rebecca binary + sqlite + nginx 3169 + node + inbound set
set -euo pipefail
DOMAIN="${DOMAIN:-${CUSTOM_DOMAIN:-}}"
APP_DIR=/opt/rebecca
ENV_FILE="$APP_DIR/.env"
DATA_DIR=/var/lib/rebecca
HERE="$(cd "$(dirname "$0")" && pwd)"
SEED_URL="${SEED_URL:-https://raw.githubusercontent.com/zedskill/PanelSetup/main/RebecSetup/seed_inbounds.py}"
SCRIPT_URL="https://raw.githubusercontent.com/rebeccapanel/Rebecca/master/scripts/rebecca/rebecca-binary.sh"
NODE_URL="https://raw.githubusercontent.com/rebeccapanel/Rebecca/master/scripts/rebecca/rebecca-node-binary.sh"
CRED_FILE=/root/rebecca-credentials.txt
ADMIN_USER="${ADMIN_USER:-adm$(openssl rand -hex 4)}"
ADMIN_PASS="${ADMIN_PASS:-Ad$(openssl rand -hex 6 | tr 'a-f' 'A-F')!x9}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl jq ca-certificates nginx libnginx-mod-stream certbot openssl python3 >/dev/null || true

curl -fsSL "$SCRIPT_URL" -o /tmp/rebecca-binary.sh
python3 - << 'PY'
from pathlib import Path
p = Path("/tmp/rebecca-binary.sh")
t = p.read_text()
if "follow_rebecca_logs() {" in t and "return 0  # RebecSetup" not in t:
    t = t.replace("follow_rebecca_logs() {", "follow_rebecca_logs() {\n    return 0  # RebecSetup", 1)
if "prompt_ssl_setup() {" in t and "[ -t 0 ] || return  # RebecSetup" not in t:
    t = t.replace("prompt_ssl_setup() {", "prompt_ssl_setup() {\n    [ -t 0 ] || return  # RebecSetup", 1)
p.write_text(t)
PY
chmod +x /tmp/rebecca-binary.sh
bash /tmp/rebecca-binary.sh install --binary --database sqlite --version latest

mkdir -p "$APP_DIR"
touch "$ENV_FILE"
upsert() {
  local k="$1" v="$2"
  if grep -q "^${k}=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^${k}=.*|${k}=${v}|" "$ENV_FILE"
  else
    echo "${k}=${v}" >> "$ENV_FILE"
  fi
}
upsert UVICORN_HOST 127.0.0.1
upsert UVICORN_PORT 8000
sed -i '/^UVICORN_SSL_CERTFILE=/d;/^UVICORN_SSL_KEYFILE=/d' "$ENV_FILE" || true
systemctl enable --now rebecca.service
systemctl restart rebecca.service || true

IP=$(hostname -I | awk '{print $1}')
CERT="/etc/letsencrypt/live/${DOMAIN:-x}/fullchain.pem"
KEY="/etc/letsencrypt/live/${DOMAIN:-x}/privkey.pem"
mkdir -p /var/www/acme /etc/nginx/stream.d

write_http_only() {
  cat > /etc/nginx/sites-available/rebecca << 'NGEOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    location /.well-known/acme-challenge/ { root /var/www/acme; }
    location / { return 301 http://$host:3169$request_uri; }
}
server {
    listen 3169 default_server;
    listen [::]:3169 default_server;
    client_max_body_size 32m;
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
    }
}
NGEOF
}

if [ -n "$DOMAIN" ]; then
  write_http_only
  ln -sfn /etc/nginx/sites-available/rebecca /etc/nginx/sites-enabled/rebecca
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl reload nginx
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
    cat > /etc/nginx/sites-available/rebecca << NGEOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/acme; }
    location / { return 301 https://\\$host\\$request_uri; }
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
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \\$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \\$host;
        proxy_set_header X-Real-IP \\$remote_addr;
        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 3600s;
    }
}
NGEOF
    cat > /etc/nginx/stream.d/rebecca-sni.conf << SNEOF
map \\$ssl_preread_server_name \\$rb_sni_upstream {
    ${DOMAIN} 127.0.0.1:10443;
    default 127.0.0.1:10444;
}
server {
    listen 443;
    listen [::]:443;
    ssl_preread on;
    proxy_pass \\$rb_sni_upstream;
    proxy_connect_timeout 5s;
}
SNEOF
  fi
else
  write_http_only
fi

ln -sfn /etc/nginx/sites-available/rebecca /etc/nginx/sites-enabled/rebecca
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/remnawave || true
nginx -t && systemctl reload nginx

for i in $(seq 1 40); do
  CODE=$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/dashboard/ || echo 000)
  echo "$CODE" | grep -qE '200|307|302|401' && break
  sleep 2
done

set -a
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && . "$ENV_FILE" || true
set +a
rebecca cli admin create --username "$ADMIN_USER" --password "$ADMIN_PASS" --role full_access || true

if [ -n "$DOMAIN" ] && [ -f "$CERT" ]; then
  R443=10444
else
  R443=443
fi

export ADMIN_USER ADMIN_PASS HOST_IP="$IP" R443 REBECCA_PANEL=http://127.0.0.1:8000
SEED="$HERE/seed_inbounds.py"
if [ ! -f "$SEED" ]; then
  curl -fsSL "$SEED_URL" -o /tmp/rebecca-seed_inbounds.py
  SEED=/tmp/rebecca-seed_inbounds.py
fi
python3 "$SEED"

curl -fsSL "$NODE_URL" -o /tmp/rebecca-node-binary.sh
python3 - << 'PY'
from pathlib import Path
p = Path("/tmp/rebecca-node-binary.sh")
t = p.read_text()
if "follow_rebecca_node_logs() {" in t and "return 0  # RebecSetup" not in t:
    t = t.replace("follow_rebecca_node_logs() {", "follow_rebecca_node_logs() {\n    return 0  # RebecSetup", 1)
if "prompt_node_port_setting() {" in t and "[ -t 0 ] || { echo" not in t:
    t = t.replace(
        "prompt_node_port_setting() {",
        'prompt_node_port_setting() {\n    [ -t 0 ] || { echo "${3}"; return 0; }  # RebecSetup',
        1,
    )
p.write_text(t)
PY
chmod +x /tmp/rebecca-node-binary.sh
if [ ! -x /opt/rebecca-node/bin/rebecca-node ] && [ ! -f /etc/systemd/system/rebecca-node.service ]; then
  bash /tmp/rebecca-node-binary.sh install --binary --version latest || true
  systemctl enable --now rebecca-node.service 2>/dev/null || true
fi
python3 "$SEED"

for p in 80 443 3169 5000 5001 5002 5003 62050 62051 8443 8444 10444; do
  iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$p" -j ACCEPT
done
iptables -C INPUT -p udp --dport 5003 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 5003 -j ACCEPT

if [ -n "$DOMAIN" ] && [ -f "$CERT" ]; then
  PANEL_URL="https://${DOMAIN}/dashboard/"
else
  PANEL_URL="http://${IP}:3169/dashboard/"
fi
{
  echo "Rebecca Panel Credentials"
  echo "============================"
  echo "Panel URL  : ${PANEL_URL}"
  echo "Username   : ${ADMIN_USER}"
  echo "Password   : ${ADMIN_PASS}"
  echo ""
  echo "VLESS TCP REALITY ${IP}:${R443}"
  echo "VLESS gRPC REALITY ${IP}:8443"
  echo "VLESS XHTTP REALITY ${IP}:8444"
  echo "VLESS TCP ${IP}:5000"
  echo "VMess TCP ${IP}:5001"
  echo "Trojan TCP ${IP}:5002"
  echo "Shadowsocks ${IP}:5003"
} > "$CRED_FILE"
chmod 600 "$CRED_FILE"

echo ""
echo "============================="
echo "Panel: ${PANEL_URL}"
echo "Username: ${ADMIN_USER}"
echo "Password: ${ADMIN_PASS}"
echo "Credentials: ${CRED_FILE}"
echo "============================="
