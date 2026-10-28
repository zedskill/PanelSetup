<div align="center">

# 3xuiSetup

One-shot [3x-ui](https://github.com/MHSanaei/3x-ui) installer: official script, **SQLite**, same inbound set as PasarSetup / MarzSetup. Optional domain + Let's Encrypt.

</div>

---

### Install

IP (HTTP :3169):

```bash
sudo bash /root/3xuiSetup/install.sh
```

Domain + Let's Encrypt + HTTPS. DNS A must already point here (grey cloud if Cloudflare):

```bash
DOMAIN=panel.example.com sudo -E bash /root/3xuiSetup/install.sh
```

`:443` SNI = domain → panel; other SNI → Reality on 10444. UDP 443 is not claimed.

Official installer is **piped from a file**. SQLite. On ~2 GB RAM stop other panels first.

Credentials: `/root/3xui-credentials.txt`

---

### Protocols

| Inbound | Port | Notes |
|---------|------|-------|
| VLESS TCP REALITY | **443** | Microsoft dest (domain install → 10444) |
| VLESS gRPC REALITY | 8443 | |
| VLESS XHTTP REALITY | 8444 | |
| VLESS TCP | 5000 | |
| VMess TCP | 5001 | |
| Trojan TCP | 5002 | |
| Shadowsocks | 5003 | chacha20-ietf-poly1305 tcp/udp |

Client `default` attached to all inbounds.

Same family as RebecSetup / PasarSetup / MarzSetup / RemnaSetup.
