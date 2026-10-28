#!/usr/bin/env python3
"""PasarSetup inbound set: Reality×3 + VLESS/VMess/Trojan/SS + hosts + service + local node."""
import base64, json, os, subprocess, sys, time, urllib.error, urllib.parse, urllib.request

DEST = "www.microsoft.com:443"
SNI = "www.microsoft.com"
PANEL = os.environ.get("REBECCA_PANEL", "http://127.0.0.1:8000")
USER = os.environ["ADMIN_USER"]
PASS = os.environ["ADMIN_PASS"]
HOST_IP = os.environ.get("HOST_IP", "127.0.0.1")
R443 = int(os.environ.get("R443", "443"))


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def x25519():
    pem = subprocess.check_output(["openssl", "genpkey", "-algorithm", "X25519"], stderr=subprocess.DEVNULL)
    priv = subprocess.check_output(["openssl", "pkey", "-outform", "DER"], input=pem)
    pub = subprocess.check_output(["openssl", "pkey", "-pubout", "-outform", "DER"], input=pem)
    return b64url(priv[-32:]), b64url(pub[-32:])


def short_id():
    return subprocess.check_output(["openssl", "rand", "-hex", "4"], text=True).strip()


class Api:
    def __init__(self, base):
        self.base = base.rstrip("/")
        self.token = None

    def call(self, method, path, body=None, form=None):
        headers = {}
        data = None
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        if form is not None:
            data = urllib.parse.urlencode(form).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        elif body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.base + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                raw = r.read().decode() or "{}"
                try:
                    return r.status, json.loads(raw)
                except Exception:
                    return r.status, raw
        except urllib.error.HTTPError as e:
            raw = e.read().decode()
            try:
                return e.code, json.loads(raw)
            except Exception:
                return e.code, {"detail": raw[:400]}


def sniff():
    return {"enabled": True, "destOverride": ["http", "tls", "quic"], "routeOnly": False}


def reality(priv, network):
    rs = {
        "show": False,
        "dest": DEST,
        "serverNames": [SNI, "microsoft.com"],
        "privateKey": priv,
        "shortIds": [short_id()],
    }
    ss = {"network": network, "security": "reality", "realitySettings": rs}
    if network == "tcp":
        ss["tcpSettings"] = {"header": {"type": "none"}}
    elif network == "grpc":
        ss["grpcSettings"] = {"serviceName": "grpc"}
    elif network == "xhttp":
        ss["xhttpSettings"] = {"path": "/", "mode": "auto"}
    return ss


def tcp_none():
    return {"network": "tcp", "security": "none", "tcpSettings": {"header": {"type": "none"}}}


def inbound(tag, port, protocol, settings, stream=None):
    o = {
        "tag": tag,
        "listen": "0.0.0.0",
        "port": port,
        "protocol": protocol,
        "settings": settings,
        "sniffing": sniff(),
    }
    if stream is not None:
        o["streamSettings"] = stream
    return o


def main():
    api = Api(PANEL)
    code, tok = api.call("POST", "/api/admin/token", {"username": USER, "password": PASS})
    if not isinstance(tok, dict) or not tok.get("access_token"):
        code, tok = api.call("POST", "/api/admin/token", form={"username": USER, "password": PASS, "grant_type": "password"})
    token = tok.get("access_token") if isinstance(tok, dict) else None
    if not token:
        raise SystemExit(f"token fail {code} {tok}")
    api.token = token

    code, listed = api.call("GET", "/api/inbounds")
    existing = set()
    if isinstance(listed, dict):
        for rows in listed.values():
            if isinstance(rows, list):
                for row in rows:
                    if isinstance(row, dict) and row.get("tag"):
                        existing.add(row["tag"])
    priv, pub = x25519()
    items = [
        inbound("VLESS TCP REALITY", R443, "vless",
                {"clients": [], "decryption": "none", "fallbacks": []}, reality(priv, "tcp")),
        inbound("VLESS gRPC REALITY", 8443, "vless",
                {"clients": [], "decryption": "none", "fallbacks": []}, reality(priv, "grpc")),
        inbound("VLESS XHTTP REALITY", 8444, "vless",
                {"clients": [], "decryption": "none", "fallbacks": []}, reality(priv, "xhttp")),
        inbound("VLESS TCP", 5000, "vless",
                {"clients": [], "decryption": "none", "fallbacks": []}, tcp_none()),
        inbound("VMess TCP", 5001, "vmess",
                {"clients": [], "disableInsecureEncryption": False}, tcp_none()),
        inbound("Trojan TCP", 5002, "trojan",
                {"clients": [], "fallbacks": []}, tcp_none()),
        inbound("Shadowsocks TCP", 5003, "shadowsocks",
                {"clients": [], "method": "chacha20-ietf-poly1305", "network": "tcp,udp"}),
    ]
    tags = []
    for it in items:
        tags.append(it["tag"])
        if it["tag"] in existing:
            print("inbound exists", it["tag"])
            continue
        code, resp = api.call("POST", "/api/inbounds", it)
        ok = code in (200, 201)
        print("inbound", it["tag"], it["port"], code, ok, str(resp)[:180])
        if not ok:
            raise SystemExit("inbound failed " + it["tag"])

    host_body = {}
    for tag, port in [
        ("VLESS TCP REALITY", R443),
        ("VLESS gRPC REALITY", 8443),
        ("VLESS XHTTP REALITY", 8444),
        ("VLESS TCP", 5000),
        ("VMess TCP", 5001),
        ("Trojan TCP", 5002),
        ("Shadowsocks TCP", 5003),
    ]:
        h = {"remark": tag, "address": HOST_IP, "port": port, "fingerprint": "chrome"}
        if "REALITY" in tag:
            h["sni"] = SNI
            h["security"] = "reality"
        host_body[tag] = [h]
    code, hosts = api.call("PUT", "/api/hosts", host_body)
    print("hosts", code, str(hosts)[:200])
    if code not in (200, 201):
        raise SystemExit("hosts failed")

    host_ids = []
    if isinstance(hosts, dict):
        for tag in tags:
            for h in hosts.get(tag) or []:
                if isinstance(h, dict) and h.get("id"):
                    host_ids.append({"host_id": h["id"]})
    if not host_ids:
        code, grouped = api.call("GET", "/api/hosts")
        if isinstance(grouped, dict):
            for tag in tags:
                for h in grouped.get(tag) or []:
                    if isinstance(h, dict) and h.get("id"):
                        host_ids.append({"host_id": h["id"]})

    code, svcs = api.call("GET", "/api/v2/services")
    have = False
    if isinstance(svcs, list):
        have = any(isinstance(s, dict) and s.get("name") == "default" for s in svcs)
    elif isinstance(svcs, dict):
        rows = svcs.get("services") or svcs.get("items") or []
        have = any(isinstance(s, dict) and s.get("name") == "default" for s in rows)
    if not have:
        code, resp = api.call("POST", "/api/v2/services", {"name": "default", "hosts": host_ids})
        print("service", code, str(resp)[:200])
        if code not in (200, 201):
            raise SystemExit("service failed")
    else:
        print("service default exists")

    code, nodes = api.call("GET", "/api/nodes")
    have_node = False
    if isinstance(nodes, list):
        have_node = any(isinstance(n, dict) and n.get("name") == "local" for n in nodes)
    elif isinstance(nodes, dict):
        rows = nodes.get("nodes") or nodes.get("items") or []
        have_node = any(isinstance(n, dict) and n.get("name") == "local" for n in rows)
    cert_pem = "/var/lib/rebecca-node/cert.pem"
    cert_key = "/var/lib/rebecca-node/cert.key"
    token_file = "/var/lib/rebecca-node/certificate_token"
    binary_ok = os.path.exists("/opt/rebecca-node/bin/rebecca-node") or os.path.exists(
        "/etc/systemd/system/rebecca-node.service"
    )
    if not have_node:
        token_cert = None
        if os.path.isfile(token_file):
            token_cert = open(token_file).read().strip() or None
        if not token_cert or not os.path.isfile(cert_pem):
            code, pending = api.call("POST", "/api/node/certificate/new")
            print("cert", code, isinstance(pending, dict))
            if not isinstance(pending, dict) or not pending.get("certificate_token"):
                raise SystemExit("cert new failed " + str(pending)[:200])
            os.makedirs("/var/lib/rebecca-node", exist_ok=True)
            open(cert_pem, "w").write(pending["certificate"])
            open(cert_key, "w").write(pending["certificate_key"])
            os.chmod(cert_key, 0o600)
            token_cert = pending["certificate_token"]
            open(token_file, "w").write(token_cert)
            os.chmod(token_file, 0o600)
        if not binary_ok:
            print("node binary missing, cert written — install.sh installs binary next")
        else:
            code, node = api.call("POST", "/api/node", {
                "name": "local",
                "address": "127.0.0.1",
                "port": 62050,
                "control_port": 62050,
                "api_port": 62051,
                "usage_coefficient": 1,
                "certificate_token": token_cert,
            })
            print("node", code, str(node)[:200])
            if code not in (200, 201):
                raise SystemExit("node failed")
    else:
        print("node local exists")

    api.call("POST", "/api/core/restart")
    print("seed done")


if __name__ == "__main__":
    main()
