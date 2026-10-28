#!/bin/bash
set -e

[[ $EUID -ne 0 ]] && { echo "Run as root: sudo bash install.sh"; exit 1; }

DASH_PORT=3169
PANEL_PORT=8000
CUSTOM_DOMAIN="${DOMAIN:-}"
[ -n "${1:-}" ] && [[ "$1" != -* ]] && CUSTOM_DOMAIN="$1"
CUSTOM_DOMAIN="${CUSTOM_DOMAIN#http://}"
CUSTOM_DOMAIN="${CUSTOM_DOMAIN#https://}"
CUSTOM_DOMAIN="${CUSTOM_DOMAIN%%/*}"
ADMIN_USER=adm$(openssl rand -hex 4)
# PasarGuard owner policy: ≥2 uppercase + special
ADMIN_PASS="Ad$(openssl rand -hex 6 | tr 'a-f' 'A-F')!x9"
NODE_API_KEY=$(cat /proc/sys/kernel/random/uuid)
HOST_IP=$(curl -4 -s --max-time 5 ifconfig.me || curl -4 -s --max-time 5 icanhazip.com || hostname -I | awk '{print $1}')
CRED_FILE="/root/pasarguard-credentials.txt"
[ -z "$HOST_IP" ] && { echo "Could not detect server IP."; exit 1; }

if [ -n "$CUSTOM_DOMAIN" ]; then
    echo "PasarSetup on $HOST_IP DOMAIN $CUSTOM_DOMAIN (LE + HTTPS SNI :443)"
else
    echo "PasarSetup on $HOST_IP (official PasarGuard sqlite --no-ssl + local node)"
fi

if ! docker --version &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl start docker && systemctl enable docker
fi

curl -fsSL https://github.com/PasarGuard/scripts/raw/main/pasarguard.sh -o /tmp/pg-official.sh
python3 - << 'PY'
from pathlib import Path
p = Path("/tmp/pg-official.sh")
t = p.read_text()
if "\n    follow_pasarguard_logs\n" not in t:
    raise SystemExit("panel follow_logs call not found — official installer changed")
t = t.replace("\n    follow_pasarguard_logs\n", "\n    true\n", 1)
old = 'read -p "Do you want to install PasarGuard node? (y/n) " install_node_choice'
new = 'install_node_choice="n"'
if old not in t:
    raise SystemExit("panel script prompt not found — official installer changed")
p.write_text(t.replace(old, new, 1))
PY
bash /tmp/pg-official.sh install --no-ssl

python3 - << PY
from pathlib import Path
import re
p = Path("/opt/pasarguard/.env")
text = p.read_text()
def setv(key, val, text):
    pat = re.compile(r'^[#[ ]*'+re.escape(key)+r'\s*=.*$', re.M)
    line = f'{key} = "{val}"'
    if pat.search(text):
        return pat.sub(line, text, count=1)
    return text.rstrip()+"\n"+line+"\n"
# production blocks env SUDO admin — keep commented
text = re.sub(r'^[#[ ]*SUDO_USERNAME\s*=.*$', '# SUDO_USERNAME = "unused"', text, flags=re.M)
text = re.sub(r'^[#[ ]*SUDO_PASSWORD\s*=.*$', '# SUDO_PASSWORD = "unused"', text, flags=re.M)
text = setv("UVICORN_HOST", "127.0.0.1", text)
text = setv("UVICORN_PORT", "$PANEL_PORT", text)
text = setv("ALLOWED_ORIGINS", "*", text)
p.write_text(text)
p.chmod(0o600)
print("env patched")
PY
cd /opt/pasarguard && docker compose -p pasarguard up -d
sleep 4

which nginx &>/dev/null || { DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >/dev/null; }
mkdir -p /var/www/acme
LISTEN80=""
[ -n "$CUSTOM_DOMAIN" ] && LISTEN80="    listen 80 default_server;
    listen [::]:80 default_server;"
cat > /etc/nginx/sites-available/pasarguard << NGEOF
server {
${LISTEN80}
    listen ${DASH_PORT} default_server;
    listen [::]:${DASH_PORT} default_server;
    location /.well-known/acme-challenge/ { root /var/www/acme; }
    location /statics/ { proxy_pass http://127.0.0.1:${PANEL_PORT}/statics/; proxy_http_version 1.1; proxy_set_header Host \$host; }
    location /sub/ { proxy_pass http://127.0.0.1:${PANEL_PORT}/sub/; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_buffering off; }
    location /dashboard/ {
        proxy_pass http://127.0.0.1:${PANEL_PORT}/dashboard/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location /dashboard { return 301 /dashboard/; }
    location /api/ {
        proxy_pass http://127.0.0.1:${PANEL_PORT}/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
    }
}
NGEOF
ln -sf /etc/nginx/sites-available/pasarguard /etc/nginx/sites-enabled/pasarguard
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/marzban
nginx -t && systemctl restart nginx

curl -fsSL https://github.com/PasarGuard/scripts/raw/main/pg-node.sh -o /tmp/pg-node-official.sh
python3 - << 'PY'
from pathlib import Path
p = Path("/tmp/pg-node-official.sh")
t = p.read_text()
p.write_text(t.replace("\n    show_node_logs\n", "\n    true\n", 1))
PY
bash /tmp/pg-node-official.sh install -y --self-signed --install-service \
    --api-key "$NODE_API_KEY" --service-port 62050 --use-grpc

for i in $(seq 1 40); do
    CODE=$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:${PANEL_PORT}/dashboard/ || echo 000)
    [ "$CODE" = "200" ] || [ "$CODE" = "307" ] && break
    sleep 3
done

export ADMIN_USER ADMIN_PASS HOST_IP CUSTOM_DOMAIN
python3 - << 'PY'
import json, os, re, time, urllib.parse, urllib.request, pathlib, subprocess

HOST = "http://127.0.0.1:8000"
user, pw = os.environ["ADMIN_USER"], os.environ["ADMIN_PASS"]
host_ip = os.environ["HOST_IP"]
custom = os.environ.get("CUSTOM_DOMAIN") or ""

def call(method, path, data=None, token=None, form=False):
    headers = {}
    body = None
    if token:
        headers["Authorization"] = "Bearer " + token
    if form:
        body = urllib.parse.urlencode(data).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    elif data is not None:
        body = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"
    r = urllib.request.Request(HOST + path, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(r, timeout=40) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:800]

out = subprocess.check_output(
    ["docker", "exec", "pasarguard-pasarguard-1", "pasarguard-cli", "generate-temp-key"],
    text=True, timeout=30)
key = re.search(r"Temp key:\s*(\S+)", out).group(1)
code, created = call("POST", "/api/setup/owner", {"key": key, "username": user, "password": pw})
print("owner", code)
if code not in (200, 201):
    raise SystemExit("owner create failed")
code, tokd = call("POST", "/api/admin/token", {"username": user, "password": pw}, form=True)
tok = tokd.get("access_token") if isinstance(tokd, dict) else None
if not tok:
    raise SystemExit("no token")

names = subprocess.check_output(["docker", "ps", "--format", "{{.Names}}"], text=True)
node = [n for n in names.splitlines() if n == "node"] or [n for n in names.splitlines() if "node" in n.lower()]
xout = subprocess.check_output(["docker", "exec", node[0], "xray", "x25519"], text=True, timeout=20)
priv = pub = ""
for line in xout.splitlines():
    if "Private" in line:
        priv = line.split(":")[-1].strip()
    if "Public" in line:
        pub = line.split(":")[-1].strip()
sid = os.urandom(8).hex()
pathlib.Path("/var/lib/pasarguard").mkdir(parents=True, exist_ok=True)
pathlib.Path("/var/lib/pasarguard/reality.env").write_text(
    f"PRIVATE={priv}\nPUBLIC={pub}\nSHORTID={sid}\nDEST=www.microsoft.com\n")
os.chmod("/var/lib/pasarguard/reality.env", 0o600)

sniff = {"enabled": True, "destOverride": ["http", "tls", "quic"]}
real = {
    "show": False, "dest": "www.microsoft.com:443", "xver": 0,
    "serverNames": ["www.microsoft.com", "microsoft.com", "www.apple.com"],
    "privateKey": priv, "shortIds": [sid, ""], "spiderX": "/",
}

def vless(tag, port, net, sec="none", path="/xhttp", svc="grpc"):
    ss = {"network": net, "security": sec}
    if net == "tcp" and sec == "none":
        ss["tcpSettings"] = {"header": {"type": "none"}}
    elif net == "tcp" and sec == "reality":
        ss = {"network": "tcp", "tcpSettings": {}, "security": "reality", "realitySettings": real}
    elif net == "grpc":
        ss["grpcSettings"] = {"serviceName": svc}
        if sec == "reality":
            ss["realitySettings"] = real
    elif net == "xhttp":
        ss["xhttpSettings"] = {"path": path, "mode": "auto"}
        if sec == "reality":
            ss["realitySettings"] = real
    listen = "127.0.0.1" if (port == 10444) else "0.0.0.0"
    return {"tag": tag, "listen": listen, "port": port, "protocol": "vless",
            "settings": {"clients": [], "decryption": "none"},
            "streamSettings": ss, "sniffing": sniff}

def other(tag, port, proto):
    o = {"tag": tag, "listen": "0.0.0.0", "port": port, "protocol": proto,
         "settings": {"clients": []}, "sniffing": sniff}
    if proto == "shadowsocks":
        o["settings"] = {"method": "chacha20-ietf-poly1305", "network": "tcp,udp", "clients": []}
        return o
    o["streamSettings"] = {"network": "tcp", "security": "none", "tcpSettings": {"header": {"type": "none"}}}
    return o

cfg = {
    "log": {"loglevel": "warning"},
    "inbounds": [
        vless("VLESS TCP REALITY", 10444 if custom else 443, "tcp", "reality"),
        vless("VLESS gRPC REALITY", 8443, "grpc", "reality"),
        vless("VLESS XHTTP REALITY", 8444, "xhttp", "reality"),
        vless("VLESS TCP", 5000, "tcp"),
        other("VMess TCP", 5001, "vmess"),
        other("Trojan TCP", 5002, "trojan"),
        other("Shadowsocks TCP", 5003, "shadowsocks"),
    ],
    "outbounds": [{"tag": "direct", "protocol": "freedom"}, {"tag": "block", "protocol": "blackhole"}],
    "routing": {"domainStrategy": "IPIfNonMatch", "rules": []},
}

code, cores = call("GET", "/api/cores", token=tok)
core_id = None
if isinstance(cores, dict) and cores.get("cores"):
    core_id = cores["cores"][0]["id"]
    call("PUT", f"/api/core/{core_id}?restart_nodes=false", {
        "name": cores["cores"][0].get("name") or "Default",
        "config": cfg, "exclude_inbound_tags": [], "fallbacks_inbound_tags": [],
    }, token=tok)
else:
    code, created = call("POST", "/api/core", {
        "name": "Default", "config": cfg, "exclude_inbound_tags": [], "fallbacks_inbound_tags": [],
    }, token=tok)
    core_id = created.get("id") if isinstance(created, dict) else None
print("core_id", core_id)
if not core_id:
    raise SystemExit("no core")

cert = open("/var/lib/pg-node/certs/ssl_cert.pem").read().strip()
api_key = None
for line in open("/opt/pg-node/.env"):
    if line.startswith("API_KEY"):
        api_key = line.split("=", 1)[1].strip().strip('"')
code, node = call("POST", "/api/node", {
    "name": "local", "address": "127.0.0.1", "port": 62050, "api_port": 62051,
    "usage_coefficient": 1, "connection_type": "grpc", "server_ca": cert,
    "keep_alive": 60, "core_config_id": core_id, "api_key": api_key,
}, token=tok)
print("node", code)
call("POST", f"/api/core/{core_id}/restart", token=tok)
time.sleep(3)

tags = ["VLESS TCP REALITY", "VLESS gRPC REALITY", "VLESS XHTTP REALITY",
        "VLESS TCP", "VMess TCP", "Trojan TCP", "Shadowsocks TCP"]
call("POST", "/api/group", {"name": "default", "inbound_tags": tags}, token=tok)
ports = {
    "VLESS TCP REALITY": 443, "VLESS gRPC REALITY": 8443, "VLESS XHTTP REALITY": 8444,
    "VLESS TCP": 5000, "VMess TCP": 5001, "Trojan TCP": 5002, "Shadowsocks TCP": 5003,
}
for i, tag in enumerate(tags, 1):
    payload = {"remark": tag, "address": [host_ip], "port": ports[tag],
               "inbound_tag": tag, "priority": i}
    if "REALITY" in tag:
        payload["sni"] = ["www.microsoft.com"]
        payload["fingerprint"] = "chrome"
    st, _ = call("POST", "/api/host/", payload, token=tok)
    print("host", tag, st)

for p in [80, 443, 3169, 5000, 5001, 5002, 5003, 62050, 62051, 8443, 8444]:
    subprocess.call(f"iptables -C INPUT -p tcp --dport {p} -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport {p} -j ACCEPT", shell=True)
subprocess.call("iptables -C INPUT -p udp --dport 5003 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 5003 -j ACCEPT", shell=True)
print("apply done")
PY

if [ -n "$CUSTOM_DOMAIN" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot libnginx-mod-stream >/dev/null || \
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot >/dev/null
    iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    if ! certbot certonly --webroot -w /var/www/acme -d "$CUSTOM_DOMAIN" \
            --non-interactive --agree-tos --register-unsafely-without-email; then
        echo "CERTBOT FAILED. DNS A $CUSTOM_DOMAIN → $HOST_IP and :80 open."
        exit 1
    fi
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
    cat > /etc/nginx/sites-available/pasarguard << NGEOF
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
    location /statics/ { proxy_pass http://127.0.0.1:${PANEL_PORT}/statics/; proxy_http_version 1.1; proxy_set_header Host \$host; }
    location /sub/ { proxy_pass http://127.0.0.1:${PANEL_PORT}/sub/; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_buffering off; }
    location /dashboard/ {
        proxy_pass http://127.0.0.1:${PANEL_PORT}/dashboard/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }
    location /dashboard { return 301 /dashboard/; }
    location /api/ {
        proxy_pass http://127.0.0.1:${PANEL_PORT}/api/;
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

if [ -n "$CUSTOM_DOMAIN" ]; then
    PANEL_URL="https://${CUSTOM_DOMAIN}/dashboard/"
else
    PANEL_URL="http://${HOST_IP}:${DASH_PORT}/dashboard/"
fi
{
  echo "PasarGuard Panel Credentials"
  echo "============================"
  echo "Panel URL  : ${PANEL_URL}"
  echo "Username   : ${ADMIN_USER}"
  echo "Password   : ${ADMIN_PASS}"
  echo ""
  echo "Reality dest/SNI : www.microsoft.com"
  echo "VLESS TCP REALITY ${HOST_IP}:443"
  echo "VLESS gRPC REALITY ${HOST_IP}:8443"
  echo "VLESS XHTTP REALITY ${HOST_IP}:8444"
  echo "VLESS TCP ${HOST_IP}:5000"
  echo "VMess TCP ${HOST_IP}:5001"
  echo "Trojan TCP ${HOST_IP}:5002"
  echo "Shadowsocks ${HOST_IP}:5003"
} > "$CRED_FILE"
chmod 600 "$CRED_FILE"

echo ""
echo "============================="
echo "Panel: ${PANEL_URL}"
echo "Username: ${ADMIN_USER}"
echo "Password: ${ADMIN_PASS}"
echo "Credentials: ${CRED_FILE}"
echo "============================="
