<div align="center">

[English](README.md) · **Русский** · [Türkçe](README.tr.md) · [فارسی](README.fa.md)

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

Однострочные установщики пяти панелей. Официальные скрипты, SQLite, Nginx на **3169**, набор inbound, опционально домен и Let’s Encrypt.

</div>

---

## Установка

Запускайте от **root** на чистом Debian / Ubuntu. Выберите **одну** панель. Не ставьте несколько панелей на 2 ГБ RAM.

### IP (без домена)

HTTP-дашборд на порту `3169`.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
```

### Домен + HTTPS

Сначала DNS **A**. Если Cloudflare — только DNS (серое облако). Затем:

```bash
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
```

TCP **443** разделяется по SNI: имя панели — Nginx TLS; остальной SNI — Reality (`10444`). UDP 443 не занимается.

В URL замените `PasarSetup` на `MarzSetup`, `RebecSetup`, `RemnaSetup` или `3xuiSetup`.

Учётные данные выводятся в конце и пишутся в `/root/*-credentials.txt`.

---

## Панели

<table>
<tr>
<td width="88" align="center"><img src="assets/pasarguard.jpg" width="56" height="56" alt="PasarGuard"></td>
<td>

**PasarGuard** — официальная панель + локальная нода, inbound, hosts.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
```

</td>
</tr>
<tr>
<td align="center"><img src="assets/marzban.png" width="56" height="56" alt="Marzban"></td>
<td>

**Marzban** — Docker Compose, админ, Nginx, inbound.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/MarzSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/MarzSetup/install.sh)"
```

</td>
</tr>
<tr>
<td align="center"><img src="assets/rebecca.jpg" width="56" height="56" alt="Rebecca"></td>
<td>

**Rebecca** — официальный binary, SQLite, локальная нода, админ, inbound.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RebecSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RebecSetup/install.sh)"
```

</td>
</tr>
<tr>
<td align="center"><img src="assets/remnawave.jpg" width="56" height="56" alt="Remnawave"></td>
<td>

**Remnawave** — официальный production compose, локальная нода, inbound.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RemnaSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RemnaSetup/install.sh)"
```

</td>
</tr>
<tr>
<td align="center"><img src="assets/3xui.png" width="56" height="56" alt="3x-ui"></td>
<td>

**3x-ui** — официальный установщик, SQLite, inbound, клиент `default`.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/3xuiSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/3xuiSetup/install.sh)"
```

</td>
</tr>
</table>

---

## Набор inbound

| Inbound | Порт | Примечание |
|---------|------|------------|
| VLESS TCP REALITY | **443** | dest Microsoft (с доменом → `10444` + SNI split) |
| VLESS gRPC REALITY | 8443 | |
| VLESS XHTTP REALITY | 8444 | |
| VLESS TCP | 5000 | |
| VMess TCP | 5001 | |
| Trojan TCP | 5002 | |
| Shadowsocks | 5003 | chacha20-ietf-poly1305, TCP+UDP |

Dest Reality — **не** Cloudflare.

Дашборд: `http://<ip>:3169/` или `https://<domain>/`.

---

## Требования

- Debian или Ubuntu, root
- ~2 ГБ свободной RAM
- Порты `80`, `443`, `3169`, `5000–5003`, `8443`, `8444`
- Режим домена: DNS **A** уже указывает на VPS

---

## Замечания

- Скрипты качают официальный установщик в файл и запускают его.
- Оранжевое облако Cloudflare на имени панели ломает ACME HTTP-01. Только DNS.
- Одна панель на маленький VPS. Только SQLite.

Исходники: [Marzban](https://github.com/Gozargah/Marzban) · [PasarGuard](https://github.com/PasarGuard/panel) · [Rebecca](https://github.com/rebeccapanel/Rebecca) · [Remnawave](https://docs.rw/) · [3x-ui](https://github.com/MHSanaei/3x-ui)
