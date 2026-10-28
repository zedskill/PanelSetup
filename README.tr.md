<div align="center">

[English](README.md) · [Русский](README.ru.md) · **Türkçe** · [فارسی](README.fa.md)

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

Beş proxy paneli için tek komutluk kurulum. Resmi kaynak betikleri, SQLite, Nginx **3169**, inbound seti, isteğe bağlı alan adı ve Let’s Encrypt.

</div>

---

## Kurulum

Temiz bir Debian / Ubuntu VPS üzerinde **root** olarak çalıştırın. **Tek** panel seçin. 2 GB sunucuda birden fazla panel kurmayın.

### IP (alan adı yok)

HTTP panel, port `3169`.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
```

### Alan adı + HTTPS

Önce DNS **A** kaydı. Cloudflare kullanıyorsanız kayıt **yalnız DNS** (gri bulut) olsun. Sonra:

```bash
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
```

TCP **443** SNI ile ayrılır: panel ana bilgisayar adı Nginx TLS; diğer SNI Reality (`10444`). UDP 443 boş bırakılır.

URL içindeki `PasarSetup` yerine `MarzSetup`, `RebecSetup`, `RemnaSetup` veya `3xuiSetup` yazın.

Kimlik bilgileri kurulum sonunda yazdırılır ve `/root/*-credentials.txt` dosyasına kaydedilir.

---

## Paneller

<table>
<tr>
<td width="88" align="center"><img src="assets/pasarguard.jpg" width="56" height="56" alt="PasarGuard"></td>
<td>

**PasarGuard** — resmi panel + yerel düğüm, inbound, host.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
```

</td>
</tr>
<tr>
<td align="center"><img src="assets/marzban.png" width="56" height="56" alt="Marzban"></td>
<td>

**Marzban** — Docker Compose, yönetici hesabı, Nginx, inbound.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/MarzSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/MarzSetup/install.sh)"
```

</td>
</tr>
<tr>
<td align="center"><img src="assets/rebecca.jpg" width="56" height="56" alt="Rebecca"></td>
<td>

**Rebecca** — resmi ikili, SQLite, yerel düğüm, yönetici, inbound.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RebecSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RebecSetup/install.sh)"
```

</td>
</tr>
<tr>
<td align="center"><img src="assets/remnawave.jpg" width="56" height="56" alt="Remnawave"></td>
<td>

**Remnawave** — resmi üretim compose, yerel düğüm, inbound.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RemnaSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RemnaSetup/install.sh)"
```

</td>
</tr>
<tr>
<td align="center"><img src="assets/3xui.png" width="56" height="56" alt="3x-ui"></td>
<td>

**3x-ui** — resmi kurulum, SQLite, inbound, `default` istemci.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/3xuiSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/3xuiSetup/install.sh)"
```

</td>
</tr>
</table>

---

## Inbound seti

| Inbound | Port | Not |
|---------|------|-----|
| VLESS TCP REALITY | **443** | Microsoft dest (alan adlı kurulum → `10444` + SNI ayrımı) |
| VLESS gRPC REALITY | 8443 | |
| VLESS XHTTP REALITY | 8444 | |
| VLESS TCP | 5000 | |
| VMess TCP | 5001 | |
| Trojan TCP | 5002 | |
| Shadowsocks | 5003 | chacha20-ietf-poly1305, TCP+UDP |

Reality hedefi Cloudflare **değildir**.

Panel: `http://<ip>:3169/` veya `https://<domain>/`.

---

## Gereksinimler

- Debian veya Ubuntu, root
- ~2 GB boş RAM
- Portlar `80`, `443`, `3169`, `5000–5003`, `8443`, `8444`
- Alan adı modu: DNS **A** kaydı betikten önce VPS’i göstermelidir

---

## Notlar

- Betikler resmi kurucuyu dosyaya indirip çalıştırır.
- Panel adında Cloudflare turuncu bulut, ACME HTTP-01’i keser. Yalnız DNS kullanın.
- Küçük VPS’te tek panel. Yalnız SQLite.

Kaynak: [Marzban](https://github.com/Gozargah/Marzban) · [PasarGuard](https://github.com/PasarGuard/panel) · [Rebecca](https://github.com/rebeccapanel/Rebecca) · [Remnawave](https://docs.rw/) · [3x-ui](https://github.com/MHSanaei/3x-ui)
