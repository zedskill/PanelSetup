#!/usr/bin/env python3
"""Inbound set: Reality x3 + VLESS/VMess/Trojan/SS via 3x-ui API."""
import json, os, re, subprocess, sys, urllib.request, urllib.error

ENV = "/etc/x-ui/install-result.env"
XRAY = "/usr/local/x-ui/bin/xray-linux-amd64"
DEST = "www.microsoft.com:443"
SNI = ["www.microsoft.com", "microsoft.com"]


def envmap():
    d = {}
    for line in open(ENV):
        line = line.strip()
        if not line or "=" not in line:
            continue
        k, v = line.split("=", 1)
        d[k] = v.strip().strip("'\"")
    return d


def x25519():
    out = subprocess.check_output([XRAY, "x25519"], text=True)
    priv = pub = None
    for line in out.splitlines():
        if "PrivateKey" in line:
            priv = line.split(":", 1)[1].strip()
        if "Password" in line or "PublicKey" in line:
            pub = line.split(":", 1)[1].strip()
    if not priv or not pub:
        raise SystemExit("x25519 failed")
    return priv, pub


def short_id():
    return subprocess.check_output(["openssl", "rand", "-hex", "4"], text=True).strip()


def port_free(p):
    r = subprocess.run(f"ss -lntu | awk '{{print $5}}' | grep -E ':{p}$'", shell=True, capture_output=True, text=True)
    return r.returncode != 0


class Api:
    def __init__(self, base, token):
        self.base = base.rstrip("/")
        self.token = token

    def call(self, method, path, body=None):
        data = None
        headers = {"Authorization": "Bearer " + self.token, "Accept": "application/json"}
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.base + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.status, json.loads(r.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            raw = e.read().decode()
            try:
                return e.code, json.loads(raw)
            except Exception:
                return e.code, {"success": False, "msg": raw[:400]}


def sniff():
    return {
        "enabled": True,
        "destOverride": ["http", "tls", "quic", "fakedns"],
        "metadataOnly": False,
        "routeOnly": False,
    }


def reality(priv, pub, sid, network):
    rs = {
        "show": False,
        "xver": 0,
        "target": DEST,
        "dest": DEST,
        "serverNames": SNI,
        "privateKey": priv,
        "shortIds": [sid],
        "settings": {
            "publicKey": pub,
            "fingerprint": "chrome",
            "serverName": "",
            "spiderX": "/",
        },
    }
    ss = {"network": network, "security": "reality", "realitySettings": rs, "externalProxy": []}
    if network == "tcp":
        ss["tcpSettings"] = {"acceptProxyProtocol": False, "header": {"type": "none"}}
    elif network == "grpc":
        ss["grpcSettings"] = {
            "serviceName": "grpc",
            "multiMode": False,
            "idle_timeout": 60,
            "health_check_timeout": 20,
            "permit_without_stream": False,
            "initial_windows_size": 0,
        }
    elif network == "xhttp":
        ss["xhttpSettings"] = {"path": "/", "host": "", "mode": "auto"}
    return ss


def tcp_none():
    return {
        "network": "tcp",
        "security": "none",
        "tcpSettings": {"acceptProxyProtocol": False, "header": {"type": "none"}},
        "externalProxy": [],
    }


def inbound(remark, port, protocol, settings, stream):
    return {
        "enable": True,
        "remark": remark,
        "listen": "",
        "port": port,
        "protocol": protocol,
        "expiryTime": 0,
        "total": 0,
        "settings": settings,
        "streamSettings": stream,
        "sniffing": sniff(),
    }


def main():
    e = envmap()
    port = e.get("XUI_PANEL_PORT", "2053")
    path = e.get("XUI_WEB_BASE_PATH", "").strip("/")
    token = e.get("XUI_API_TOKEN")
    if not token:
        raise SystemExit("no api token")
    base = f"http://127.0.0.1:{port}/{path}" if path else f"http://127.0.0.1:{port}"
    api = Api(base, token)

    st, listed = api.call("GET", "/panel/api/inbounds/list")
    existing = {(x.get("remark"), x.get("port")) for x in (listed.get("obj") or [])}
    if any(r.startswith("VLESS ") or r.startswith("Shadowsocks") for r, _ in existing):
        print("inbounds already seeded")
        ids = [x["id"] for x in listed.get("obj") or []]
    else:
        priv, pub = x25519()
        sid = short_id()
        if os.environ.get("DOMAIN") or os.environ.get("R443"):
            r443 = int(os.environ.get("R443") or "10444")
        else:
            r443 = 443 if port_free(443) else 10444
        items = [
            inbound("VLESS TCP REALITY", r443, "vless",
                    {"clients": [], "decryption": "none", "fallbacks": []},
                    reality(priv, pub, sid, "tcp")),
            inbound("VLESS gRPC REALITY", 8443, "vless",
                    {"clients": [], "decryption": "none", "fallbacks": []},
                    reality(priv, pub, sid, "grpc")),
            inbound("VLESS XHTTP REALITY", 8444, "vless",
                    {"clients": [], "decryption": "none", "fallbacks": []},
                    reality(priv, pub, sid, "xhttp")),
            inbound("VLESS TCP", 5000, "vless",
                    {"clients": [], "decryption": "none", "fallbacks": []},
                    tcp_none()),
            inbound("VMess TCP", 5001, "vmess",
                    {"clients": [], "disableInsecureEncryption": False},
                    tcp_none()),
            inbound("Trojan TCP", 5002, "trojan",
                    {"clients": [], "fallbacks": []},
                    tcp_none()),
            inbound("Shadowsocks TCP", 5003, "shadowsocks",
                    {"clients": [], "method": "chacha20-ietf-poly1305", "network": "tcp,udp", "ivCheck": False},
                    None),
        ]
        ids = []
        for it in items:
            if it["streamSettings"] is None:
                it.pop("streamSettings")
            code, resp = api.call("POST", "/panel/api/inbounds/add", it)
            ok = bool(resp.get("success"))
            print("inbound", it["remark"], it["port"], code, ok, resp.get("msg", "")[:200])
            if not ok:
                raise SystemExit("inbound failed: " + it["remark"])
            obj = resp.get("obj") or {}
            iid = obj.get("id")
            if iid:
                ids.append(iid)
        if not ids:
            st, listed = api.call("GET", "/panel/api/inbounds/list")
            ids = [x["id"] for x in listed.get("obj") or []]

    # Domain/SNI split: Reality cannot occupy :443
    want443 = int(os.environ.get("R443") or "0")
    if os.environ.get("DOMAIN") and not want443:
        want443 = 10444
    if want443:
        st, listed = api.call("GET", "/panel/api/inbounds/list")
        for x in listed.get("obj") or []:
            if x.get("remark") == "VLESS TCP REALITY" and int(x.get("port") or 0) != want443:
                st, full = api.call("GET", f"/panel/api/inbounds/get/{x['id']}")
                obj = full.get("obj") or {}
                payload = {
                    "enable": True,
                    "remark": obj.get("remark"),
                    "listen": obj.get("listen") or "",
                    "port": want443,
                    "protocol": obj.get("protocol"),
                    "expiryTime": obj.get("expiryTime") or 0,
                    "total": obj.get("total") or 0,
                    "settings": obj.get("settings"),
                    "streamSettings": obj.get("streamSettings"),
                    "sniffing": obj.get("sniffing"),
                }
                code, resp = api.call("POST", f"/panel/api/inbounds/update/{x['id']}", payload)
                print("move reality", x.get("port"), "->", want443, code, resp.get("success"), str(resp.get("msg", ""))[:120])

    st, cl = api.call("GET", "/panel/api/clients/list")
    emails = []
    obj = cl.get("obj")
    if isinstance(obj, dict):
        emails = [c.get("email") for c in (obj.get("clients") or obj.get("obj") or [])]
    elif isinstance(obj, list):
        emails = [c.get("email") for c in obj]
    if "default" not in emails:
        code, resp = api.call("POST", "/panel/api/clients/add", {
            "client": {"email": "default", "enable": True, "totalGB": 0, "expiryTime": 0, "limitIp": 0, "tgId": 0},
            "inboundIds": ids,
        })
        print("client default", code, resp.get("success"), resp.get("msg", "")[:200])
        if not resp.get("success"):
            raise SystemExit("client add failed")
    else:
        print("client default exists")

    for p in [80, 443, 5000, 5001, 5002, 5003, 8443, 8444, 10444]:
        subprocess.call(
            f"iptables -C INPUT -p tcp --dport {p} -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport {p} -j ACCEPT",
            shell=True,
        )
    subprocess.call(
        "iptables -C INPUT -p udp --dport 5003 -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport 5003 -j ACCEPT",
        shell=True,
    )
    print("seed done", "ids", ids)


if __name__ == "__main__":
    main()
