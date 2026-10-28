<div align="center">

# RebecSetup

One-shot [Rebecca](https://github.com/rebeccapanel/Rebecca) installer: official **binary**, **SQLite**, Nginx **3169**, local node, same inbound set as PasarSetup / 3xuiSetup.

</div>

---

### Install

```bash
sudo bash /root/RebecSetup/install.sh
```

Domain + Let's Encrypt (DNS A already pointing, CF grey):

```bash
DOMAIN=panel.example.com sudo -E bash /root/RebecSetup/install.sh
```

Official installer is **piped from a file**. SQLite. On ~2 GB RAM stop other panels first.

Credentials: `/root/rebecca-credentials.txt`

---

### What it does

| Step | Action |
|------|--------|
| 1 | Official Rebecca binary (`sqlite`) |
| 2 | Nginx reverse proxy on `3169` |
| 3 | Admin (`full_access`) |
| 4 | Local `rebecca-node` binary :62050 |
| 5 | Inbounds + hosts + service `default` |

---

### Protocols

| Inbound | Port | Notes |
|---------|------|-------|
| VLESS TCP REALITY | **443** | dest Microsoft (domain/443 busy → 10444) |
| VLESS gRPC REALITY | 8443 | |
| VLESS XHTTP REALITY | 8444 | |
| VLESS TCP | 5000 | |
| VMess TCP | 5001 | |
| Trojan TCP | 5002 | |
| Shadowsocks | 5003 | chacha20-ietf-poly1305 tcp/udp |

Dashboard: `http://<ip>:3169/dashboard/` or `https://<domain>/dashboard/`

Same family as 3xuiSetup / PasarSetup / MarzSetup / RemnaSetup.
