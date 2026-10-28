<div align="center">

# PasarSetup

One-shot [PasarGuard](https://github.com/PasarGuard/panel) installer: official `pasarguard.sh` + local node + Nginx dashboard + inbound set.

</div>

---

### Install

IP / HTTP :3169:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PasarSetup/main/install.sh)"
```

Domain + Let's Encrypt + HTTPS (same SNI split as MarzSetup / RemnaSetup). DNS A → VPS first (CF grey cloud):

```bash
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PasarSetup/main/install.sh)"
```

---

### What it does

| Step | Action |
|------|--------|
| 1 | Official PasarGuard panel (`sqlite`, `--no-ssl`) |
| 2 | Official `pg-node` on the same host (self-signed, test VPS only) |
| 3 | Nginx reverse proxy on port `3169` |
| 4 | Owner account (temp-key) + core inbounds (TCP / SS / Reality Microsoft dest) + hosts |
| 5 | Credentials → `/root/pasarguard-credentials.txt` |

2 GB VPS: SQLite only. Do not install TimescaleDB here. Do not run next to Marzban on the same 2 GB box.

---

### Protocols

Same practical set as MarzSetup. HTTP/2 raw inbound is omitted (Xray 24+). Reality dest is **`www.microsoft.com` / `www.apple.com`**, not Cloudflare.

TLS-on-`sslip.io` is not used (blocked on some networks). Plaintext WS/gRPC omitted (DPI).

| Inbound | Port | Notes |
|---------|------|-------|
| VLESS TCP REALITY | **443** | dest/SNI `www.microsoft.com` |
| VLESS gRPC REALITY | 8443 | |
| VLESS XHTTP REALITY | 8444 | |
| VLESS TCP | 5000 | |
| VMess TCP | 5001 | |
| Trojan TCP | 5002 | |
| Shadowsocks | 5003 | chacha20-ietf-poly1305 tcp/udp |

Dashboard: port **3169**.

---

### Requirements

- Debian / Ubuntu VPS, root
- ~2 GB RAM free (stop other panels first)
- Ports 80/443/3169/5000–5003/62050/8000/8443/8444

Based on [PasarGuard](https://github.com/PasarGuard/panel).
