#!/bin/bash
set -e

[[ $EUID -ne 0 ]] && { echo "Run as root: sudo bash install.sh"; exit 1; }

DASH_PORT=3169
XRAY_PORT=8080
CUSTOM_DOMAIN="${DOMAIN:-}"
[ -n "${1:-}" ] && [[ "$1" != -* ]] && CUSTOM_DOMAIN="$1"
CUSTOM_DOMAIN="${CUSTOM_DOMAIN#http://}"
CUSTOM_DOMAIN="${CUSTOM_DOMAIN#https://}"
CUSTOM_DOMAIN="${CUSTOM_DOMAIN%%/*}"
ADMIN_USER=adm$(openssl rand -hex 4)
ADMIN_PASS=$(openssl rand -hex 12)
HOST_IP=$(curl -4 -s --max-time 5 ifconfig.me || curl -4 -s --max-time 5 icanhazip.com || hostname -I | awk '{print $1}')
CRED_FILE="/root/marzban-credentials.txt"
CERT_DIR="/var/lib/marzban/certs"
REALITY_DEST="www.microsoft.com"
REALITY_SNIS='["www.microsoft.com", "microsoft.com", "www.apple.com"]'

[ -z "$HOST_IP" ] && { echo "Could not detect server IP."; exit 1; }
if [ -n "$CUSTOM_DOMAIN" ]; then
    echo "Installing on $HOST_IP DOMAIN $CUSTOM_DOMAIN (LE + HTTPS SNI :443)"
else
    echo "Installing on $HOST_IP (HTTP :$DASH_PORT)"
fi

if ! docker --version &>/dev/null; then
    echo "[1/7] Installing Docker ..."
    curl -fsSL https://get.docker.com | sh
    systemctl start docker && systemctl enable docker
else
    echo "[1/7] Docker OK"
fi

echo "[2/7] Installing Marzban ..."
mkdir -p /opt/marzban /var/lib/marzban "$CERT_DIR"

cat > /var/lib/marzban/xray_config.json << 'XEOF'
{"log":{"loglevel":"warning"},"api":{"tag":"api","services":["HandlerService","LoggerService","StatsService"]},"stats":{},"inbounds":[{"tag":"api","listen":"127.0.0.1","port":62789,"protocol":"dokodemo-door","settings":{"address":"127.0.0.1"}}],"outbounds":[{"tag":"direct","protocol":"freedom"},{"tag":"block","protocol":"blackhole"}],"routing":{"rules":[{"inboundTag":["api"],"outboundTag":"api","type":"field"}]}}
XEOF

cat > /opt/marzban/.env << ENVEOF
UVICORN_HOST=127.0.0.1
UVICORN_PORT=${XRAY_PORT}
DASHBOARD_PATH=/dashboard/
SUDO_USERNAME=${ADMIN_USER}
SUDO_PASSWORD=${ADMIN_PASS}
MARZBAN_ADMIN_USERNAME=${ADMIN_USER}
MARZBAN_ADMIN_PASSWORD=${ADMIN_PASS}
ENVEOF

cat > /opt/marzban/docker-compose.yml << 'YMLEOF'
services:
  marzban:
    image: gozargah/marzban:latest
    container_name: marzban-marzban-1
    restart: always
    network_mode: host
    env_file: .env
    volumes:
      - /var/lib/marzban:/var/lib/marzban
      - /opt/marzban:/opt/marzban
YMLEOF

cd /opt/marzban
docker compose down >/dev/null 2>&1 || true
sleep 2
docker compose up -d

echo "[3/7] Waiting for panel ..."
for i in $(seq 1 30); do
    sleep 3
    CODE=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${XRAY_PORT}/" 2>/dev/null) || CODE=000
    [ "$CODE" = "200" ] || [ "$CODE" = "307" ] || [ "$CODE" = "404" ] && break
done

echo "[4/7] Creating admin ..."
docker exec -e MARZBAN_ADMIN_PASSWORD="$ADMIN_PASS" marzban-marzban-1 \
    marzban-cli admin create -u "$ADMIN_USER" --sudo --telegram-id 0 --discord-webhook "" \
    >/dev/null 2>&1 || true
sleep 2

token_req() {
    curl -s -X POST "http://127.0.0.1:${XRAY_PORT}/api/admin/token" \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        -d "username=${ADMIN_USER}&password=${ADMIN_PASS}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || true
}
TOKEN=$(token_req)
[ -z "$TOKEN" ] && sleep 5 && TOKEN=$(token_req)
[ -n "$TOKEN" ] || { echo "Failed to get admin token."; exit 1; }

echo "[5/7] Setting up Nginx ..."
which nginx &>/dev/null || { DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >/dev/null 2>&1; }
systemctl enable nginx
systemctl start nginx 2>/dev/null || systemctl restart nginx
LISTEN80=""
[ -n "$CUSTOM_DOMAIN" ] && LISTEN80="    listen 80 default_server;
    listen [::]:80 default_server;"
cat > /etc/nginx/sites-available/marzban << NGEOF
server {
${LISTEN80}
    listen ${DASH_PORT} default_server;
    listen [::]:${DASH_PORT} default_server;
    location /.well-known/acme-challenge/ { root /var/www/acme; }
    location /statics/ { proxy_pass http://127.0.0.1:${XRAY_PORT}/statics/; proxy_http_version 1.1; proxy_set_header Host \$host; }
    location /sub/ { proxy_pass http://127.0.0.1:${XRAY_PORT}/sub/; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_buffering off; }
    location /dashboard/ {
        proxy_pass http://127.0.0.1:${XRAY_PORT}/dashboard/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location /dashboard { return 301 /dashboard/; }
    location /api/ {
        proxy_pass http://127.0.0.1:${XRAY_PORT}/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
    }
}
NGEOF
mkdir -p /var/www/acme
ln -sf /etc/nginx/sites-available/marzban /etc/nginx/sites-enabled/marzban
rm -f /etc/nginx/sites-enabled/default
nginx -t 2>/dev/null && systemctl restart nginx

echo "[6/7] TLS certificate ..."
TLS_OK=0
if [ -n "$CUSTOM_DOMAIN" ]; then
    DOMAIN="$CUSTOM_DOMAIN"
else
    DOMAIN="${HOST_IP}.sslip.io"
fi
PATH=/usr/sbin:/sbin:$PATH
iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 80 -j ACCEPT
if [ -n "$CUSTOM_DOMAIN" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot libnginx-mod-stream >/dev/null || \
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot >/dev/null
    if certbot certonly --webroot -w /var/www/acme -d "$CUSTOM_DOMAIN" \
            --non-interactive --agree-tos --register-unsafely-without-email; then
        cp "/etc/letsencrypt/live/${CUSTOM_DOMAIN}/fullchain.pem" "$CERT_DIR/fullchain.pem"
        cp "/etc/letsencrypt/live/${CUSTOM_DOMAIN}/privkey.pem" "$CERT_DIR/key.pem"
        TLS_OK=1
        echo "TLS cert OK: $CUSTOM_DOMAIN"
    else
        echo "CERTBOT FAILED. DNS A $CUSTOM_DOMAIN must point to $HOST_IP and :80 open."
        exit 1
    fi
elif [ ! -f /root/.acme.sh/acme.sh ]; then
    curl -fsSL https://get.acme.sh | sh -s email=admin@${DOMAIN} >/dev/null 2>&1 || true
fi
if [ -z "$CUSTOM_DOMAIN" ] && [ -x /root/.acme.sh/acme.sh ]; then
    fuser -k 80/tcp >/dev/null 2>&1 || true
    sleep 1
    if /root/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --httpport 80 --server letsencrypt --keylength 2048; then
        /root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
            --fullchain-file "$CERT_DIR/fullchain.pem" --key-file "$CERT_DIR/key.pem"
        TLS_OK=1
        echo "TLS cert OK: $DOMAIN"
    else
        echo "TLS cert failed — Reality still works; WS/gRPC TLS skipped"
    fi
fi

echo "[7/7] Creating inbounds ..."
RAW=$(docker exec marzban-marzban-1 xray x25519)
PRIV=$(printf '%s\n' "$RAW" | awk -F': ' 'BEGIN{IGNORECASE=1} /Private key/{print $2}')
PUB=$(printf '%s\n' "$RAW" | awk -F': ' 'BEGIN{IGNORECASE=1} /Public key/{print $2}')
SID=$(openssl rand -hex 8)
printf 'PRIVATE=%s\nPUBLIC=%s\nSHORTID=%s\nDEST=%s\n' "$PRIV" "$PUB" "$SID" "$REALITY_DEST" > /var/lib/marzban/reality.env
chmod 600 /var/lib/marzban/reality.env

export CUSTOM_DOMAIN
python3 - "$PRIV" "$PUB" "$SID" "$TLS_OK" "$DOMAIN" "$CERT_DIR" << 'PY'
import json, sys, os
pk, pub, sid, tls_ok, domain, cert_dir = sys.argv[1:7]
tls = tls_ok == "1" and os.path.exists(os.path.join(cert_dir, "fullchain.pem"))
custom = os.environ.get("CUSTOM_DOMAIN") or ""
sniff = {"enabled": True, "destOverride": ["http", "tls", "quic"]}
real = {
    "show": False, "dest": "www.microsoft.com:443", "xver": 0,
    "serverNames": ["www.microsoft.com", "microsoft.com", "www.apple.com"],
    "privateKey": pk, "publicKey": pub, "shortIds": [sid, ""], "spiderX": "/",
}
tlsset = {"certificates": [{"certificateFile": os.path.join(cert_dir, "fullchain.pem"),
                            "keyFile": os.path.join(cert_dir, "key.pem")}], "minVersion": "1.2"}

def st(net, sec="none", path=None, svc=None):
    ss = {"network": net, "security": sec}
    if net == "tcp" and sec == "none":
        ss["tcpSettings"] = {"header": {"type": "none"}}
    elif net == "tcp" and sec == "reality":
        ss = {"network": "tcp", "tcpSettings": {}, "security": "reality", "realitySettings": real}
    elif net == "ws":
        ss["wsSettings"] = {"path": path or "/ws", "host": domain if sec == "tls" else ""}
        if sec == "tls":
            ss["tlsSettings"] = tlsset
    elif net == "grpc":
        ss["grpcSettings"] = {"serviceName": svc or "grpc"}
        if sec == "reality":
            ss["realitySettings"] = real
        if sec == "tls":
            ss["tlsSettings"] = tlsset
    elif net == "xhttp":
        ss["xhttpSettings"] = {"path": path or "/xhttp", "mode": "auto"}
        if sec == "tls":
            ss["xhttpSettings"]["host"] = domain
        if sec == "reality":
            ss["realitySettings"] = real
        if sec == "tls":
            ss["tlsSettings"] = tlsset
    elif net == "httpupgrade":
        ss["httpupgradeSettings"] = {"path": path or "/hu", "host": domain if sec == "tls" else ""}
        if sec == "tls":
            ss["tlsSettings"] = tlsset
    return ss

def vless(tag, port, net, sec="none", listen="0.0.0.0", **kw):
    return {"tag": tag, "listen": listen, "port": port, "protocol": "vless",
            "settings": {"clients": [], "decryption": "none", "fallbacks": []},
            "streamSettings": st(net, sec, **kw), "sniffing": sniff}

def vmess(tag, port, net, sec="none", **kw):
    return {"tag": tag, "listen": "0.0.0.0", "port": port, "protocol": "vmess",
            "settings": {"clients": []}, "streamSettings": st(net, sec, **kw), "sniffing": sniff}

def trojan(tag, port, net, sec="none", **kw):
    return {"tag": tag, "listen": "0.0.0.0", "port": port, "protocol": "trojan",
            "settings": {"clients": []}, "streamSettings": st(net, sec, **kw), "sniffing": sniff}

inbounds = [
    {"tag": "api", "listen": "127.0.0.1", "port": 62789, "protocol": "dokodemo-door",
     "settings": {"address": "127.0.0.1"}},
    vless("VLESS TCP REALITY", 10444 if custom else 443, "tcp", "reality",
          listen="127.0.0.1" if custom else "0.0.0.0"),
    vless("VLESS gRPC REALITY", 8443, "grpc", "reality", svc="grpc"),
    vless("VLESS XHTTP REALITY", 8444, "xhttp", "reality", path="/xhttp"),
    vless("VLESS TCP", 5000, "tcp"),
    vmess("VMess TCP", 5001, "tcp"),
    trojan("Trojan TCP", 5002, "tcp"),
    {"tag": "Shadowsocks TCP", "listen": "0.0.0.0", "port": 5003, "protocol": "shadowsocks",
     "settings": {"method": "chacha20-ietf-poly1305", "network": "tcp,udp", "clients": []},
     "sniffing": sniff},
]
if tls:
    inbounds += [
        vless("VLESS WS TLS", 2053, "ws", "tls", path="/vlessws"),
        vless("VLESS gRPC TLS", 2054, "grpc", "tls", svc="vlessgrpc"),
        vless("VLESS XHTTP TLS", 2055, "xhttp", "tls", path="/xhttptls"),
        vless("VLESS HTTPUpgrade TLS", 2056, "httpupgrade", "tls", path="/hu"),
        vmess("VMess WS TLS", 2083, "ws", "tls", path="/vmessws"),
        vmess("VMess gRPC TLS", 2087, "grpc", "tls", svc="vmessgrpc"),
        trojan("Trojan WS TLS", 2088, "ws", "tls", path="/trojanws"),
        trojan("Trojan gRPC TLS", 2096, "grpc", "tls", svc="trojangrpc"),
    ]

cfg = {
    "log": {"loglevel": "warning"},
    "api": {"tag": "api", "services": ["HandlerService", "LoggerService", "StatsService"]},
    "stats": {},
    "policy": {"levels": {"0": {"statsUserUplink": True, "statsUserDownlink": True}},
               "system": {"statsInboundUplink": True, "statsInboundDownlink": True,
                          "statsOutboundUplink": True, "statsOutboundDownlink": True}},
    "routing": {"domainStrategy": "IPIfNonMatch",
                "rules": [{"inboundTag": ["api"], "outboundTag": "api", "type": "field"}]},
    "inbounds": inbounds,
    "outbounds": [
        {"tag": "api", "protocol": "freedom"},
        {"tag": "direct", "protocol": "freedom"},
        {"tag": "block", "protocol": "blackhole"},
    ],
}
open("/tmp/xray_cfg.json", "w").write(json.dumps(cfg))
print("inbounds", len(cfg["inbounds"]) - 1, "tls", tls)
PY

PUT=$(curl -s -o /tmp/xray_put.out -w '%{http_code}' -X PUT "http://127.0.0.1:${XRAY_PORT}/api/core/config" \
    -H 'Content-Type: application/json' -H "Authorization: Bearer ${TOKEN}" -d @/tmp/xray_cfg.json)
echo "core config HTTP $PUT"
[ "$PUT" = "200" ] || cat /tmp/xray_put.out
cp /tmp/xray_cfg.json /var/lib/marzban/xray_config.json
rm -f /tmp/xray_cfg.json /tmp/xray_put.out

if [ -n "$CUSTOM_DOMAIN" ] && [ "$TLS_OK" = "1" ]; then
    python3 - << 'PY'
from pathlib import Path
p = Path("/etc/nginx/nginx.conf")
t = p.read_text()
if "include /etc/nginx/stream.d/" not in t:
    p.write_text(t.rstrip() + "\n\nstream {\n    include /etc/nginx/stream.d/*.conf;\n}\n")
PY
    mkdir -p /etc/nginx/stream.d
    CERT="/etc/letsencrypt/live/${CUSTOM_DOMAIN}/fullchain.pem"
    KEY="/etc/letsencrypt/live/${CUSTOM_DOMAIN}/privkey.pem"
    cat > /etc/nginx/sites-available/marzban << NGEOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${CUSTOM_DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/acme; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 127.0.0.1:10443 ssl;
    listen ${DASH_PORT} ssl;
    listen [::]:${DASH_PORT} ssl;
    server_name ${CUSTOM_DOMAIN};
    http2 on;
    ssl_certificate ${CERT};
    ssl_certificate_key ${KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    location /statics/ { proxy_pass http://127.0.0.1:${XRAY_PORT}/statics/; proxy_http_version 1.1; proxy_set_header Host \$host; }
    location /sub/ { proxy_pass http://127.0.0.1:${XRAY_PORT}/sub/; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_buffering off; }
    location /dashboard/ {
        proxy_pass http://127.0.0.1:${XRAY_PORT}/dashboard/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }
    location /dashboard { return 301 /dashboard/; }
    location /api/ {
        proxy_pass http://127.0.0.1:${XRAY_PORT}/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
    }
}
NGEOF
    cat > /etc/nginx/stream.d/panel-sni.conf << SNEOF
map \$ssl_preread_server_name \$panel_sni_upstream {
    ${CUSTOM_DOMAIN} 127.0.0.1:10443;
    default 127.0.0.1:10444;
}
server {
    listen 443;
    listen [::]:443;
    ssl_preread on;
    proxy_pass \$panel_sni_upstream;
    proxy_connect_timeout 5s;
}
SNEOF
    nginx -t && systemctl reload nginx
    echo "0 3 * * * root certbot renew --quiet --deploy-hook 'systemctl reload nginx'" > /etc/cron.d/panel-certbot
fi

TCP_PORTS="80 443 3169 5000 5001 5002 5003 8443 8444"
[ "$TLS_OK" = "1" ] && TCP_PORTS="$TCP_PORTS 2053 2054 2055 2056 2083 2087 2088 2096"
for P in $TCP_PORTS; do
    iptables -C INPUT -p tcp --dport "$P" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$P" -j ACCEPT
done
iptables -C INPUT -p udp --dport 5003 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 5003 -j ACCEPT
netfilter-persistent save 2>/dev/null || true

if [ -n "$CUSTOM_DOMAIN" ]; then
    PANEL_URL="https://${CUSTOM_DOMAIN}/dashboard/"
else
    PANEL_URL="http://${HOST_IP}:${DASH_PORT}/dashboard/"
fi
{
    echo "Marzban Panel Credentials"
    echo "========================"
    echo "Panel URL  : ${PANEL_URL}"
    echo "Username   : ${ADMIN_USER}"
    echo "Password   : ${ADMIN_PASS}"
    echo ""
    echo "Reality (TM: use this first)"
    echo "----------------------------"
    echo "publicKey  : ${PUB}"
    echo "shortId    : ${SID}"
    echo "dest/SNI   : ${REALITY_DEST}  (also apple.com)"
    echo "VLESS TCP REALITY    ${HOST_IP}:443"
    echo "VLESS gRPC REALITY   ${HOST_IP}:8443"
    echo "VLESS XHTTP REALITY  ${HOST_IP}:8444"
    echo ""
    echo "Plain TCP"
    echo "---------"
    echo "VLESS TCP            ${HOST_IP}:5000"
    echo "VMess TCP            ${HOST_IP}:5001"
    echo "Trojan TCP           ${HOST_IP}:5002"
    echo "Shadowsocks          ${HOST_IP}:5003"
    if [ "$TLS_OK" = "1" ]; then
        echo ""
        echo "TLS (SNI ${DOMAIN})"
        echo "-------------------"
        echo "VLESS WS TLS         ${HOST_IP}:2053  path=/vlessws"
        echo "VLESS gRPC TLS       ${HOST_IP}:2054  svc=vlessgrpc"
        echo "VLESS XHTTP TLS      ${HOST_IP}:2055  path=/xhttptls"
        echo "VLESS HTTPUpgrade    ${HOST_IP}:2056  path=/hu"
        echo "VMess WS TLS         ${HOST_IP}:2083  path=/vmessws"
        echo "VMess gRPC TLS       ${HOST_IP}:2087"
        echo "Trojan WS TLS        ${HOST_IP}:2088  path=/trojanws"
        echo "Trojan gRPC TLS      ${HOST_IP}:2096"
    fi
} > "$CRED_FILE"
chmod 600 "$CRED_FILE"

echo ""
echo "============================="
echo "Panel: ${PANEL_URL}"
echo "Username: ${ADMIN_USER}"
echo "Password: ${ADMIN_PASS}"
echo "Credentials: ${CRED_FILE}"
echo "Reality dest: ${REALITY_DEST} :443 / :8443 / :8444"
[ "$TLS_OK" = "1" ] && echo "TLS SNI: ${DOMAIN} :2053+"
echo "============================="
