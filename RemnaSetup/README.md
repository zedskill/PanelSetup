<div align="center">

# RemnaSetup

One-shot [Remnawave](https://docs.rw/install/remnawave-panel/) panel installer: official `docker-compose-prod.yml`, Nginx **HTTP** reverse proxy on **3169**, local Remnawave Node, Reality dest **microsoft**, TCP + Shadowsocks.

[![Bash](https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Docker](https://img.shields.io/badge/runtime-docker-2496ED?style=flat-square&logo=docker&logoColor=white)](https://www.docker.com/)
[![Nginx](https://img.shields.io/badge/proxy-nginx-009639?style=flat-square&logo=nginx&logoColor=white)](https://nginx.org/)
[![Remnawave](https://img.shields.io/badge/panel-remnawave-0ea5e9?style=flat-square)](https://docs.rw/)

</div>

---

### Install

IP / no domain (HTTP :3169, test):

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/RemnaSetup/main/install.sh)"
```

Domain + Let's Encrypt + HTTPS. You point DNS; the script does vhost, certbot, SNI split:

```bash
# 1) At registrar:  A  panel.example.com  →  VPS IPv4   (grey cloud if CF)
# 2) Wait until it resolves, then:
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/RemnaSetup/main/install.sh)"
```

What domain mode does on the VPS:

1. Nginx vhost for `panel.example.com`
2. Certbot HTTP-01 on **:80** → `/etc/letsencrypt/live/...`
3. TCP **443 SNI split**: SNI=`panel.example.com` → panel HTTPS; any other SNI (Reality `www.microsoft.com`) → Xray on `127.0.0.1:8443`. Clients still connect Reality on **443**.
4. UDP 443 untouched (Hysteria)
5. Subscription stays `https://panel.example.com/api/sub/<id>` (real cert, no self-signed)

Official compose only — not DigneZzZ. On ~2 GB RAM stop other panels first. Cloudflare orange-cloud on this hostname breaks TM and ACME — DNS only.

---

### What it does

| Step | Action |
|------|--------|
| 1 | Installs Docker if missing |
| 2 | Downloads official `docker-compose-prod.yml` + `.env.sample` into `/opt/remnawave` |
| 3 | Generates `APP_SECRET` / Postgres / webhook keys; `FRONT_END_DOMAIN=*`; `SUB_PUBLIC_DOMAIN=<ip>:3169/api/sub` |
| 4 | Nginx reverse proxy on **3169** over HTTP (sends `X-Forwarded-Proto: https` so Remnawave accepts it; no sslip.io) |
| 5 | Starts panel + Postgres + Valkey |
| 6 | Registers super-admin, Default-Profile inbounds, local Node, hosts, Default-Squad |
| 7 | Starts `remnawave/node` (`network_mode: host`, API **2222**) |
| 8 | Saves credentials to `/root/remnawave-credentials.txt` |

Dashboard: `http://<ip>:3169` (IP mode) or `https://<domain>/` (DOMAIN mode).

---

### Protocols

Remnawave Node runs Xray. **Reality dest is `www.microsoft.com` — not Cloudflare.** Some networks (e.g. Turkmenistan) block Cloudflare SNI and `sslip.io`.

TM test context (2026-10): **TCP inbounds + Shadowsocks** were the working path. Reality dest microsoft is still provisioned.

| Inbound | Port | Notes |
|---------|------|-------|
| VLESS TCP REALITY | **443** | dest/SNI `www.microsoft.com` |
| VLESS TCP | 5000 | no TLS, flow disabled (vision would break it) |
| Trojan TCP | 5002 | no TLS |
| Shadowsocks | 5003 | chacha20-ietf-poly1305 tcp/udp |

Remnawave does not manage VMess users — no VMess inbound. Subscription links are rewritten to `http://` (panel itself always emits `https://`).

H2/HTTP2 inbound is omitted (Xray 24 removed it). No sslip.io ACME. UDP 443 is not claimed (leave Hysteria alone).

---

### Layout

| Path | Role |
|------|------|
| `/opt/remnawave` | Official panel compose + `.env` |
| `/opt/remnanode` | Node compose + `SECRET_KEY` |
| `/root/remnawave-credentials.txt` | Admin URL / user / password |

```bash
cd /opt/remnawave && docker compose logs -f
docker exec -it remnawave cli   # Rescue CLI
```
