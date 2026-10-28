<div align="center">

<p align="center">
  <a href="https://github.com/gozargah/marzban" target="_blank" rel="noopener noreferrer">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://github.com/Gozargah/Marzban-docs/raw/master/screenshots/logo-dark.png">
      <img width="160" height="160" src="https://github.com/Gozargah/Marzban-docs/raw/master/screenshots/logo-light.png">
    </picture>
  </a>
</p>

# MarzSetup

One-shot Marzban panel installer with Nginx reverse proxy, firewall rules and credential saving.

[![Bash](https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Docker](https://img.shields.io/badge/runtime-docker-2496ED?style=flat-square&logo=docker&logoColor=white)](https://www.docker.com/)
[![Nginx](https://img.shields.io/badge/proxy-nginx-009639?style=flat-square&logo=nginx&logoColor=white)](https://nginx.org/)
[![Marzban](https://img.shields.io/badge/panel-marzban-1a1a2e?style=flat-square)](https://github.com/gozargah/Marzban)

</div>

---

### Install

IP / HTTP :3169:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/MarzSetup/main/install.sh)"
```

Domain + Let's Encrypt + HTTPS (same SNI split as RemnaSetup / PasarSetup). DNS A → VPS first (CF grey cloud):

```bash
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/MarzSetup/main/install.sh)"
```

`:443` SNI=`panel.example.com` → panel; other SNI → Reality. UDP 443 Hysteria untouched.

---

### What it does

| Step | Action |
|------|--------|
| 1 | Installs Docker if not present |
| 2 | Deploys Marzban via Docker Compose |
| 3 | Creates admin account with random credentials |
| 4 | Configures Nginx reverse proxy on port `3169` |
| 5 | Issues Let's Encrypt cert for `<ip>.sslip.io` (standalone :80) |
| 6 | Opens Reality (Microsoft/Apple dest) + TLS WS/gRPC/XHTTP inbounds |
| 7 | Opens required ports in firewall |
| 8 | Saves credentials to `/root/marzban-credentials.txt` |

---

### Protocols

Marzban supports VLESS, VMess, Trojan, Shadowsocks. HTTP/2 raw inbound is omitted — Xray 24+ removed it (use XHTTP).

**Reality dest is `www.microsoft.com` / `www.apple.com` — not Cloudflare.** Some networks (e.g. Turkmenistan) block Cloudflare SNI.

TM test (2026-10-25): **VLESS/VMess/Trojan TCP + Shadowsocks worked.** `sslip.io` SNI/host is blocked there, so TLS WS/gRPC/XHTTP on that cert will not connect. Reality may still fail depending on client SNI; TCP+SS is the confirmed path. Plaintext WS/gRPC is omitted because DPI drops it.

If ACME fails, Reality inbounds still go live; TLS WS/gRPC are skipped.

| Inbound | Port | Notes |
|---------|------|-------|
| VLESS TCP REALITY | **443** | dest/SNI `www.microsoft.com` (also apple) |
| VLESS gRPC REALITY | 8443 | |
| VLESS XHTTP REALITY | 8444 | |
| VLESS TCP | 5000 | |
| VMess TCP | 5001 | |
| Trojan TCP | 5002 | |
| Shadowsocks | 5003 | chacha20-ietf-poly1305 tcp/udp |
| VLESS WS TLS | 2053 | path `/vlessws` SNI `<ip>.sslip.io` |
| VLESS gRPC TLS | 2054 | service `vlessgrpc` |
| VLESS XHTTP TLS | 2055 | path `/xhttptls` |
| VLESS HTTPUpgrade TLS | 2056 | path `/hu` |
| VMess WS TLS | 2083 | path `/vmessws` |
| VMess gRPC TLS | 2087 | |
| Trojan WS TLS | 2088 | path `/trojanws` |
| Trojan gRPC TLS | 2096 | |

Dashboard: port **3169**. Reality `publicKey` + `shortId` → `/root/marzban-credentials.txt`.

---

### After install

Credentials are printed to stdout and saved to:

```
/root/marzban-credentials.txt
```

Panel URL, username and password are stored there with `chmod 600`.

---

### Requirements

- Debian / Ubuntu based VPS
- Root or sudo access
- Clean server (no existing Nginx config on port 3169)
- Port 80 free during install (Let's Encrypt HTTP-01)

---

### Notes

- Dashboard path is proxied through Nginx, not exposed directly on the Marzban port.
- Admin credentials are randomly generated on every run.
- Xray core config is applied via the Marzban API after container is healthy.
- Client: Reality SNI `www.microsoft.com`, fingerprint `chrome`. TLS WS SNI = `<ip>.sslip.io`.

---

<div align="center">

Based on [Marzban](https://github.com/gozargah/Marzban) by Gozargah

</div>
