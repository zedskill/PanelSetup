<div align="center">

[English](README.md) · [Русский](README.ru.md) · [Türkçe](README.tr.md) · **فارسی**

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

نصب تک‌فرمانی پنج پنل پروکسی. اسکریپت رسمی بالادست، SQLite، Nginx روی **3169**، مجموعه inbound، دامنه اختیاری و Let’s Encrypt.

</div>

---

## نصب

روی VPS تمیز Debian / Ubuntu با **root** اجرا کنید. **یک** پنل انتخاب کنید. روی میزبان ۲ گیگابایت چند پنل نصب نکنید.

### IP (بدون دامنه)

داشبورد HTTP روی پورت `3169`.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
```

### دامنه + HTTPS

ابتدا رکورد DNS **A**. اگر Cloudflare دارید، رکورد را **فقط DNS** (ابر خاکستری) بگذارید. سپس:

```bash
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
```

TCP **443** با SNI جدا می‌شود: نام میزبان پنل در Nginx؛ سایر SNI به Reality (`10444`). UDP 443 اشغال نمی‌شود.

در URL به‌جای `PasarSetup` از `MarzSetup`، `RebecSetup`، `RemnaSetup` یا `3xuiSetup` استفاده کنید.

اطلاعات ورود در پایان چاپ و در `/root/*-credentials.txt` ذخیره می‌شود.

---

## پنل‌ها

<table>
<tr>
<td width="88" align="center"><img src="assets/pasarguard.jpg" width="56" height="56" alt="PasarGuard"></td>
<td>

**PasarGuard** — پنل رسمی + نود محلی، inbound، host.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/PasarSetup/install.sh)"
```

</td>
</tr>
<tr>
<td align="center"><img src="assets/marzban.png" width="56" height="56" alt="Marzban"></td>
<td>

**Marzban** — Docker Compose، حساب مدیر، Nginx، inbound.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/MarzSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/MarzSetup/install.sh)"
```

</td>
</tr>
<tr>
<td align="center"><img src="assets/rebecca.jpg" width="56" height="56" alt="Rebecca"></td>
<td>

**Rebecca** — باینری رسمی، SQLite، نود محلی، مدیر، inbound.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RebecSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RebecSetup/install.sh)"
```

</td>
</tr>
<tr>
<td align="center"><img src="assets/remnawave.jpg" width="56" height="56" alt="Remnawave"></td>
<td>

**Remnawave** — compose تولیدی رسمی، نود محلی، inbound.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RemnaSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/RemnaSetup/install.sh)"
```

</td>
</tr>
<tr>
<td align="center"><img src="assets/3xui.png" width="56" height="56" alt="3x-ui"></td>
<td>

**3x-ui** — نصب‌کننده رسمی، SQLite، inbound، کلاینت `default`.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/3xuiSetup/install.sh)"
DOMAIN=panel.example.com sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/zedskill/PanelSetup/main/3xuiSetup/install.sh)"
```

</td>
</tr>
</table>

---

## مجموعه inbound

| Inbound | پورت | توضیح |
|---------|------|--------|
| VLESS TCP REALITY | **443** | dest مایکروسافت (با دامنه → `10444` + تفکیک SNI) |
| VLESS gRPC REALITY | 8443 | |
| VLESS XHTTP REALITY | 8444 | |
| VLESS TCP | 5000 | |
| VMess TCP | 5001 | |
| Trojan TCP | 5002 | |
| Shadowsocks | 5003 | chacha20-ietf-poly1305، TCP+UDP |

مقصد Reality **کلودفلر نیست**.

داشبورد: `http://<ip>:3169/` یا `https://<domain>/`.

---

## پیش‌نیاز

- Debian یا Ubuntu، root
- حدود ۲ گیگابایت RAM آزاد
- پورت‌های `80`، `443`، `3169`، `5000–5003`، `8443`، `8444`
- حالت دامنه: رکورد DNS **A** قبل از اجرا به VPS اشاره کند

---

## نکات

- نصب‌کننده‌ها اسکریپت رسمی را در فایل ذخیره و سپس اجرا می‌کنند.
- ابر نارنجی Cloudflare روی نام پنل، ACME HTTP-01 را قطع می‌کند. فقط DNS.
- روی VPS کوچک فقط یک پنل. فقط SQLite.

منبع: [Marzban](https://github.com/Gozargah/Marzban) · [PasarGuard](https://github.com/PasarGuard/panel) · [Rebecca](https://github.com/rebeccapanel/Rebecca) · [Remnawave](https://docs.rw/) · [3x-ui](https://github.com/MHSanaei/3x-ui)
