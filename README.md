<div align="center">

**English** · [Русский](README.ru.md) · [Türkçe](README.tr.md) · [فارسی](README.fa.md)

<br/>

<table>
  <tr>
    <td align="center" width="120">
      <a href="https://github.com/Gozargah/Marzban"><img src="assets/marzban.png" width="72" height="72" alt="Marzban"></a><br/>
      <sub><b>Marzban</b></sub>
    </td>
    <td align="center" width="120">
      <a href="https://github.com/PasarGuard/panel"><img src="assets/pasarguard.jpg" width="72" height="72" alt="PasarGuard"></a><br/>
      <sub><b>PasarGuard</b></sub>
    </td>
    <td align="center" width="120">
      <a href="https://github.com/rebeccapanel/Rebecca"><img src="assets/rebecca.jpg" width="72" height="72" alt="Rebecca"></a><br/>
      <sub><b>Rebecca</b></sub>
    </td>
    <td align="center" width="120">
      <a href="https://docs.rw/"><img src="assets/remnawave.jpg" width="72" height="72" alt="Remnawave"></a><br/>
      <sub><b>Remnawave</b></sub>
    </td>
    <td align="center" width="120">
      <a href="https://github.com/MHSanaei/3x-ui"><img src="assets/3xui.png" width="72" height="72" alt="3x-ui"></a><br/>
      <sub><b>3x-ui</b></sub>
    </td>
  </tr>
</table>

# PanelSetup

One-shot installers for five proxy panels. Official upstream scripts, SQLite, Nginx on **3169**, inbound set, optional domain + Let’s Encrypt.

[![License](https://img.shields.io/badge/license-MIT-0f172a?style=flat-square)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Nginx](https://img.shields.io/badge/proxy-nginx-009639?style=flat-square&logo=nginx&logoColor=white)](https://nginx.org/)

</div>

---

## Install

Run as **root** on a clean Debian / Ubuntu VPS. Pick **one** panel. Do not stack panels on a 2 GB host.

### IP (no domain)

HTTP dashboard on port `3169`.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
```

### Domain + HTTPS

Create a DNS **A** record first. If you use Cloudflare, keep the record **DNS only** (grey cloud). Then:

```bash
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
```

TCP **443** is split by SNI: the panel hostname terminates TLS at Nginx; other SNI goes to Reality (listen `10444` behind the splitter). UDP 443 is left free.

Replace `PasarSetup` in the URL with `MarzSetup`, `RebecSetup`, `RemnaSetup`, or `3xuiSetup`.

Credentials are printed at the end and stored in `/root/*-credentials.txt` (`chmod 600`).

---

## Panels

<table>
<tr>
<td width="88" align="center"><img src="assets/pasarguard.jpg" width="56" height="56" alt="PasarGuard"></td>
<td>

**PasarGuard** — official panel + local node, inbound set, hosts, default group.

**IP**

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
```

**Domain**

```bash
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
```


</td>
</tr>
<tr>
<td align="center"><img src="assets/marzban.png" width="56" height="56" alt="Marzban"></td>
<td>

**Marzban** — Docker Compose, admin account, Nginx, inbound set.

**IP**

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/MarzSetup/install.sh)"
```

**Domain**

```bash
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/MarzSetup/install.sh)"
```


</td>
</tr>
<tr>
<td align="center"><img src="assets/rebecca.jpg" width="56" height="56" alt="Rebecca"></td>
<td>

**Rebecca** — official binary, SQLite, local node, admin, inbound set.

**IP**

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RebecSetup/install.sh)"
```

**Domain**

```bash
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RebecSetup/install.sh)"
```


</td>
</tr>
<tr>
<td align="center"><img src="assets/remnawave.jpg" width="56" height="56" alt="Remnawave"></td>
<td>

**Remnawave** — official production compose, local node, inbound set.

**IP**

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RemnaSetup/install.sh)"
```

**Domain**

```bash
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RemnaSetup/install.sh)"
```


</td>
</tr>
<tr>
<td align="center"><img src="assets/3xui.png" width="56" height="56" alt="3x-ui"></td>
<td>

**3x-ui** — official installer, SQLite, inbound set, client `default`.

**IP**

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/3xuiSetup/install.sh)"
```

**Domain**

```bash
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/3xuiSetup/install.sh)"
```


</td>
</tr>
</table>

---

## Inbound set

| Inbound | Port | Notes |
|---------|------|-------|
| VLESS TCP REALITY | **443** | Microsoft dest (domain install → `10444` + SNI split) |
| VLESS gRPC REALITY | 8443 | |
| VLESS XHTTP REALITY | 8444 | |
| VLESS TCP | 5000 | |
| VMess TCP | 5001 | |
| Trojan TCP | 5002 | |
| Shadowsocks | 5003 | chacha20-ietf-poly1305, TCP+UDP |

Reality destination is **not** Cloudflare.

Dashboard: `http://<ip>:3169/` or `https://<domain>/`.

---

## Requirements

- Debian or Ubuntu, root
- ~2 GB RAM free (stop other panels first)
- Ports `80`, `443`, `3169`, `5000–5003`, `8443`, `8444`
- Domain mode: DNS **A** already pointing at the VPS before you run the script

---

## Notes

- Installers download official upstream scripts to a file, then execute — not `bash -c "$(curl)"` against an oversized payload.
- Cloudflare orange-cloud on the panel hostname breaks HTTP-01 ACME. Use DNS only.
- One panel per small VPS. SQLite only; do not enable Timescale / Postgres on 2 GB.

Upstream: [Marzban](https://github.com/Gozargah/Marzban) · [PasarGuard](https://github.com/PasarGuard/panel) · [Rebecca](https://github.com/rebeccapanel/Rebecca) · [Remnawave](https://docs.rw/) · [3x-ui](https://github.com/MHSanaei/3x-ui)
