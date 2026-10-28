#!/bin/bash
set -e

[[ $EUID -ne 0 ]] && { echo "Run as root: sudo bash install.sh"; exit 1; }

DASH_PORT=3169
NODE_PORT=2222
REALITY_DEST="www.microsoft.com"
DOMAIN="${DOMAIN:-}"
[ -n "${1:-}" ] && [[ "$1" != -* ]] && DOMAIN="$1"
DOMAIN="${DOMAIN#http://}"
DOMAIN="${DOMAIN#https://}"
DOMAIN="${DOMAIN%%/*}"
HOST_IP=$(curl -4 -s --max-time 5 ifconfig.me || curl -4 -s --max-time 5 icanhazip.com || hostname -I | awk '{print $1}')
CRED_FILE="/root/remnawave-credentials.txt"
APP_DIR="/opt/remnawave"
NODE_DIR="/opt/remnanode"

[ -z "$HOST_IP" ] && { echo "Could not detect server IP."; exit 1; }
if [ -n "$DOMAIN" ]; then
    PANEL_HOST="$DOMAIN"
    SUB_HOST="${DOMAIN}/api/sub"
    echo "RemnaSetup DOMAIN $DOMAIN — Let's Encrypt + HTTPS :443 SNI (panel) / Reality (other SNI), UDP 443 HY2"
else
    PANEL_HOST="${HOST_IP}:${DASH_PORT}"
    SUB_HOST="${HOST_IP}:${DASH_PORT}/api/sub"
    echo "RemnaSetup IP $HOST_IP (HTTP :$DASH_PORT, no domain)"
fi

if ! docker --version &>/dev/null; then
    echo "[1/8] Installing Docker ..."
    curl -fsSL https://get.docker.com | sh
    systemctl start docker && systemctl enable docker
else
    echo "[1/8] Docker OK"
fi

# 2GB: do not run four panels at once
if docker ps --format '{{.Names}}' | grep -qE '^pasarguard|^marzban'; then
    echo "[2/8] Stopping other panels (keep Hysteria) ..."
    (cd /opt/pasarguard && docker compose -p pasarguard down) >/dev/null 2>&1 || true
    docker stop node >/dev/null 2>&1 || true
    (cd /opt/marzban && docker compose down) >/dev/null 2>&1 || true
else
    echo "[2/8] No other panels running"
fi

echo "[3/8] Official panel files ..."
mkdir -p "$APP_DIR/nginx" "$NODE_DIR"
cd "$APP_DIR"
curl -fsSL -o docker-compose.yml https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml
curl -fsSL -o .env https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/.env.sample
sed -i 's/shm_size: 512mb/shm_size: 128mb/' docker-compose.yml
sed -i "s/^APP_SECRET=.*/APP_SECRET=$(openssl rand -hex 64)/" .env
sed -i "s/^METRICS_PASS=.*/METRICS_PASS=$(openssl rand -hex 32)/" .env
sed -i "s/^WEBHOOK_SECRET_HEADER=.*/WEBHOOK_SECRET_HEADER=$(openssl rand -hex 32)/" .env
pw=$(openssl rand -hex 24)
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$pw/" .env
sed -i "s|^\\(DATABASE_URL=\"postgresql://postgres:\\)[^\\@]*\\(@.*\\)|\\1$pw\\2|" .env
sed -i "s|^PANEL_DOMAIN=.*|PANEL_DOMAIN=${PANEL_HOST}|" .env
sed -i "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=*|" .env
sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=${SUB_HOST}|" .env
chmod 600 .env

echo "[4/8] Nginx ..."
which nginx &>/dev/null || { DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >/dev/null; }
if [ -n "$DOMAIN" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot libnginx-mod-stream >/dev/null || \
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot >/dev/null
    mkdir -p /var/www/acme /etc/nginx/stream.d
    python3 - << 'PY'
from pathlib import Path
p = Path("/etc/nginx/nginx.conf")
t = p.read_text()
if "include /etc/nginx/stream.d/" not in t:
    p.write_text(t.rstrip() + "\n\nstream {\n    include /etc/nginx/stream.d/*.conf;\n}\n")
PY
    cat > /etc/nginx/sites-available/remnawave << NGEOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen ${DASH_PORT} default_server;
    listen [::]:${DASH_PORT} default_server;
    server_name ${DOMAIN} _;
    location /.well-known/acme-challenge/ { root /var/www/acme; }
    location / {
        proxy_pass http://127.0.0.1:3000;
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
else
    cat > /etc/nginx/sites-available/remnawave << NGEOF
server {
    listen ${DASH_PORT} default_server;
    listen [::]:${DASH_PORT} default_server;
    client_max_body_size 32m;
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_hide_header Strict-Transport-Security;
        proxy_hide_header Content-Security-Policy;
        proxy_set_header Accept-Encoding "";
        sub_filter 'https://${PANEL_HOST}' 'http://${PANEL_HOST}';
        sub_filter 'https://${HOST_IP}:${DASH_PORT}' 'http://${PANEL_HOST}';
        sub_filter_once off;
        sub_filter_types application/json text/html application/javascript text/plain;
        proxy_read_timeout 3600s;
    }
}
NGEOF
fi
ln -sf /etc/nginx/sites-available/remnawave /etc/nginx/sites-enabled/remnawave
rm -f /etc/nginx/sites-enabled/pasarguard /etc/nginx/sites-enabled/marzban /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

echo "[5/8] Starting panel ..."
docker compose pull
docker compose up -d
for i in $(seq 1 40); do
    if curl -sS --max-time 4 "http://127.0.0.1:${DASH_PORT}/api/auth/status" | grep -q isRegisterAllowed; then
        echo "Panel up"
        break
    fi
    sleep 3
    [ "$i" = 40 ] && { echo "Panel did not become ready"; docker compose logs --tail 40; exit 1; }
done

echo "[6/8] Admin + profile + node + hosts ..."
python3 -c "from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey" 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-cryptography >/dev/null
export HOST_IP DASH_PORT NODE_PORT REALITY_DEST CRED_FILE APP_DIR NODE_DIR DOMAIN PANEL_HOST
python3 - << 'PY'
import json, os, ssl, secrets, string, subprocess, time, urllib.request, urllib.error, textwrap
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives import serialization
import base64

BASE = f"http://127.0.0.1:{os.environ['DASH_PORT']}"
CTX = ssl._create_unverified_context()
IP = os.environ["HOST_IP"]
CRED = os.environ["CRED_FILE"]
NODE_DIR = os.environ["NODE_DIR"]
NODE_PORT = int(os.environ["NODE_PORT"])
DEST = os.environ["REALITY_DEST"]
HAS_DOMAIN = bool(os.environ.get("DOMAIN"))
REALITY_LISTEN = "127.0.0.1" if HAS_DOMAIN else "0.0.0.0"
REALITY_BIND = 10444 if HAS_DOMAIN else 443

def req(method, path, body=None, token=None, timeout=40):
    data = None if body is None else json.dumps(body).encode()
    h = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-Remnawave-Client-Type": "browser",
    }
    if token:
        h["Authorization"] = "Bearer " + token
    r = urllib.request.Request(BASE + path, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(r, timeout=timeout, context=CTX) as resp:
            raw = resp.read().decode()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            j = json.loads(raw)
        except Exception:
            j = {"raw": raw[:2000]}
        return e.code, j

def gen_pass(n=28):
    alphabet = string.ascii_letters + string.digits
    while True:
        p = "".join(secrets.choice(alphabet) for _ in range(n))
        if any(c.islower() for c in p) and any(c.isupper() for c in p) and any(c.isdigit() for c in p):
            return p

admin_user = "rwadmin"
admin_pass = gen_pass()
st, body = req("POST", "/api/auth/register", {
    "username": admin_user,
    "password": admin_pass,
    "email": "rwadmin@localhost.local",
})
if st not in (200, 201):
    # already registered — require existing creds
    if os.path.exists(CRED):
        env = {}
        for line in open(CRED):
            if "=" in line:
                k, v = line.strip().split("=", 1)
                env[k] = v
        admin_user = env.get("USERNAME", admin_user)
        admin_pass = env.get("PASSWORD", admin_pass)
    else:
        raise SystemExit(f"register failed {st} {body}")

st, body = req("POST", "/api/auth/login", {"username": admin_user, "password": admin_pass})
if st != 200:
    raise SystemExit(f"login failed {st} {body}")
jwt = body["response"]["accessToken"]

st, tok = req("POST", "/api/tokens", {"name": "boot", "expiresInDays": 365}, token=jwt)
api_token = (tok.get("response") or {}).get("token") if st in (200, 201) else ""

sk = X25519PrivateKey.generate()
priv = base64.urlsafe_b64encode(
    sk.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
).decode().rstrip("=")
pub = base64.urlsafe_b64encode(
    sk.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
).decode().rstrip("=")
short_id = secrets.token_hex(8)

xray = {
    "log": {"loglevel": "warning"},
    "inbounds": [
        {
            "tag": "VLESS-REALITY",
            "port": REALITY_BIND,
            "listen": REALITY_LISTEN,
            "protocol": "vless",
            "settings": {"clients": [], "decryption": "none"},
            "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]},
            "streamSettings": {
                "network": "raw",
                "security": "reality",
                "realitySettings": {
                    "target": f"{DEST}:443",
                    "shortIds": [short_id, ""],
                    "privateKey": priv,
                    "serverNames": [DEST, "microsoft.com"],
                    "minClientVer": "0.0.0",
                },
            },
        },
        {
            "tag": "VLESS-TCP",
            "port": 5000,
            "listen": "0.0.0.0",
            "protocol": "vless",
            "settings": {"clients": [], "decryption": "none", "flow": ""},
            "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]},
            "streamSettings": {"network": "raw", "security": "none"},
        },
        {
            "tag": "TROJAN-TCP",
            "port": 5002,
            "listen": "0.0.0.0",
            "protocol": "trojan",
            "settings": {"clients": []},
            "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]},
            "streamSettings": {"network": "raw", "security": "none"},
        },
        {
            "tag": "Shadowsocks",
            "port": 5003,
            "listen": "0.0.0.0",
            "protocol": "shadowsocks",
            "settings": {
                "method": "chacha20-ietf-poly1305",
                "clients": [],
                "network": "tcp,udp",
            },
            "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]},
        },
    ],
    "outbounds": [
        {"tag": "DIRECT", "protocol": "freedom"},
        {"tag": "BLOCK", "protocol": "blackhole"},
    ],
    "routing": {
        "rules": [
            {"ip": ["geoip:private"], "outboundTag": "BLOCK"},
            {"domain": ["geosite:private"], "outboundTag": "BLOCK"},
            {"protocol": ["bittorrent"], "outboundTag": "BLOCK"},
        ]
    },
}

st, profiles = req("GET", "/api/config-profiles", token=jwt)
plist = (profiles.get("response") or {}).get("configProfiles") or []
if not plist:
    raise SystemExit("no config profile")
profile_uuid = plist[0]["uuid"]
st, _ = req("PATCH", "/api/config-profiles", {"uuid": profile_uuid, "config": xray}, token=jwt)
if st not in (200, 201):
    raise SystemExit(f"patch profile {st}")

st, profiles = req("GET", "/api/config-profiles", token=jwt)
prof = (profiles.get("response") or {}).get("configProfiles")[0]
inbounds = prof.get("inbounds") or []
inbound_uuids = [i["uuid"] for i in inbounds]
by_tag = {i["tag"]: i for i in inbounds}

st, kg = req("GET", "/api/keygen", token=jwt)
secret = (kg.get("response") or {}).get("secretKey")
if not secret:
    raise SystemExit("no node SECRET_KEY from /api/keygen")

gw = subprocess.check_output(
    "docker network inspect remnawave-network --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}'",
    shell=True,
).decode().strip() or "172.17.0.1"

st, nodes = req("GET", "/api/nodes", token=jwt)
existing = nodes.get("response") or []
if isinstance(existing, dict):
    existing = existing.get("nodes") or existing.get("items") or []
node = existing[0] if existing else None
if not node:
    st, nb = req("POST", "/api/nodes", {
        "name": "local",
        "address": gw,
        "port": NODE_PORT,
        "countryCode": "NL",
        "isTrafficTrackingActive": False,
        "consumptionMultiplier": 1.0,
        "configProfile": {
            "activeConfigProfileUuid": profile_uuid,
            "activeInbounds": inbound_uuids,
        },
    }, token=jwt)
    if st not in (200, 201):
        raise SystemExit(f"create node {st} {nb}")
    node = nb.get("response") or nb
else:
    req("PATCH", "/api/nodes", {
        "uuid": node["uuid"],
        "address": gw,
        "port": NODE_PORT,
        "configProfile": {
            "activeConfigProfileUuid": profile_uuid,
            "activeInbounds": inbound_uuids,
        },
    }, token=jwt)

os.makedirs(NODE_DIR, exist_ok=True)
with open(os.path.join(NODE_DIR, ".env"), "w") as f:
    f.write(f"NODE_PORT={NODE_PORT}\nSECRET_KEY={secret}\n")
os.chmod(os.path.join(NODE_DIR, ".env"), 0o600)
with open(os.path.join(NODE_DIR, "docker-compose.yml"), "w") as f:
    f.write(textwrap.dedent(f"""\
    services:
      remnanode:
        container_name: remnanode
        hostname: remnanode
        image: remnawave/node:latest
        restart: always
        network_mode: host
        env_file: .env
        cap_add:
          - NET_ADMIN
        ulimits:
          nofile:
            soft: 1048576
            hard: 1048576
    """))

st, sq = req("GET", "/api/internal-squads", token=jwt)
squad = (sq.get("response") or {}).get("internalSquads")[0]
req("PATCH", "/api/internal-squads", {"uuid": squad["uuid"], "inbounds": inbound_uuids}, token=jwt)

st, hosts = req("GET", "/api/hosts", token=jwt)
hlist = hosts.get("response") or []
if isinstance(hlist, dict):
    hlist = hlist.get("hosts") or []
have = {h.get("remark") for h in hlist}

def add_host(remark, tag, extra=None):
    if remark in have:
        return
    ib = by_tag[tag]
    payload = {
        "remark": remark,
        "address": IP,
        "port": ib["port"],
        "inbound": {
            "configProfileUuid": profile_uuid,
            "configProfileInboundUuid": ib["uuid"],
        },
    }
    if extra:
        payload.update(extra)
    req("POST", "/api/hosts", payload, token=jwt)

add_host("REALITY", "VLESS-REALITY", {"sni": DEST, "fingerprint": "chrome", "port": 443})
add_host("VLESS-TCP", "VLESS-TCP", {"securityLayer": "NONE"})
add_host("TROJAN-TCP", "TROJAN-TCP", {"securityLayer": "NONE"})
add_host("SS", "Shadowsocks", {"securityLayer": "NONE"})

panel_host = os.environ.get("PANEL_HOST") or f"{IP}:{os.environ['DASH_PORT']}"
url_scheme = "https" if os.environ.get("DOMAIN") else "http"
with open(CRED, "w") as f:
    f.write(f"URL={url_scheme}://{panel_host}\n")
    f.write(f"USERNAME={admin_user}\nPASSWORD={admin_pass}\n")
    if api_token:
        f.write(f"API_TOKEN={api_token}\n")
    f.write(f"NODE_UUID={node.get('uuid')}\nNODE_PORT={NODE_PORT}\n")
    f.write(f"REALITY_PUBLIC={pub}\nREALITY_SHORT={short_id}\nREALITY_DEST={DEST}\n")
os.chmod(CRED, 0o600)
print("bootstrap ok")
PY

if [ -z "$DOMAIN" ]; then
echo "[6b/8] Force http:// subscription URLs (panel hardcodes https://) ..."
docker exec remnawave node -e '
const fs=require("fs");
for (const f of ["/opt/app/dist/app.js","/opt/app/dist/processors.js","/opt/app/dist/scheduler.js"]) {
  let s=fs.readFileSync(f,"utf8");
  s=s.replace(/this\.subscriptionUrl="https:\/\/"\.concat\(t,"\/"\)\.concat\(e\.shortUuid\)/g,
              "this.subscriptionUrl=\"http://\".concat(t,\"/\").concat(e.shortUuid)");
  s=s.replace(/"https:\/\/"\.concat\(this\.subPublicDomain/g, "\"http://\".concat(this.subPublicDomain");
  s=s.replace(/return"https:\/\/"\.concat\(r,"\/"\)\.concat\(e\.shortUuid\)/g,
              "return\"http://\".concat(r,\"/\").concat(e.shortUuid)");
  fs.writeFileSync(f,s);
}
'
docker restart remnawave
for i in $(seq 1 30); do
    curl -sS --max-time 4 "http://127.0.0.1:${DASH_PORT}/api/auth/status" | grep -q isLoginAllowed && break
    sleep 2
done
fi

echo "[7/8] Starting remnanode ..."
cd "$NODE_DIR"
docker compose pull
docker compose up -d
sleep 4

if [ -n "$DOMAIN" ]; then
echo "[7b/8] Let's Encrypt + HTTPS SNI on :443 ..."
iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 443 -j ACCEPT
if ! certbot certonly --webroot -w /var/www/acme -d "$DOMAIN" \
        --non-interactive --agree-tos --register-unsafely-without-email; then
    echo "CERTBOT FAILED. DNS A $DOMAIN must point to $HOST_IP and :80 must be open."
    exit 1
fi
CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.key"
cat > /etc/nginx/sites-available/remnawave << NGEOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/acme; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 127.0.0.1:10443 ssl;
    listen ${DASH_PORT} ssl;
    listen [::]:${DASH_PORT} ssl;
    server_name ${DOMAIN};
    http2 on;
    ssl_certificate ${CERT};
    ssl_certificate_key ${KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 32m;
    location / {
        proxy_pass http://127.0.0.1:3000;
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
cat > /etc/nginx/stream.d/remnawave-sni.conf << SNEOF
map \$ssl_preread_server_name \$rw_sni_upstream {
    ${DOMAIN} 127.0.0.1:10443;
    default 127.0.0.1:10444;
}
server {
    listen 443;
    listen [::]:443;
    ssl_preread on;
    proxy_pass \$rw_sni_upstream;
    proxy_connect_timeout 5s;
}
SNEOF
nginx -t && systemctl reload nginx
echo "0 3 * * * root certbot renew --quiet --deploy-hook 'systemctl reload nginx'" > /etc/cron.d/remnawave-certbot
fi

echo "[8/8] Firewall (TCP inbounds; UDP 443 left for Hysteria) ..."
for p in 443 5000 5002 5003 "$DASH_PORT"; do
    iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$p" -j ACCEPT
done
[ -n "$DOMAIN" ] && { iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 80 -j ACCEPT; }
iptables -C INPUT -p udp --dport 5003 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 5003 -j ACCEPT
# node API: localhost + docker networks
iptables -C INPUT -p tcp --dport "$NODE_PORT" -s 127.0.0.1 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$NODE_PORT" -s 127.0.0.1 -j ACCEPT
if docker network inspect remnawave-network >/dev/null 2>&1; then
    SUBNET=$(docker network inspect remnawave-network --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
    iptables -C INPUT -p tcp --dport "$NODE_PORT" -s "$SUBNET" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$NODE_PORT" -s "$SUBNET" -j ACCEPT
fi

echo
echo "Remnawave ready."
if [ -n "$DOMAIN" ]; then
    echo "  Panel: https://${DOMAIN}"
    echo "  Sub  : https://${DOMAIN}/api/sub/<id>"
else
    echo "  Panel: http://${PANEL_HOST}"
fi
echo "  Creds: ${CRED_FILE}"
echo "  Node:  remnanode  :${NODE_PORT}  Reality dest ${REALITY_DEST}"
echo "  Inbounds: TCP 443 REALITY, 5000 VLESS TCP, 5002 Trojan, 5003 SS"
