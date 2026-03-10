# PisoWifi Installation Guide

## Quick Installation (Recommended)

The easiest way to install is using the all-in-one CGI installer script.

1.  **Copy the installer to your router:**
    ```sh
    scp INSTALL_CGI.sh root@192.168.1.1:/tmp/install.sh
    ```
    *(Replace `192.168.1.1` with your router's current IP)*

2.  **Run the installer:**
    ```sh
    ssh root@192.168.1.1
    chmod +x /tmp/install.sh
    /tmp/install.sh
    ```

This script will automatically:
*   Install the captive portal (CGI version).
*   Set up the firewall with **DNS Hijacking** (redirecting unauthenticated users to the portal).
*   Configure the Coin Slot (WPS Button).
*   Set up the redirect page.

---

## Manual Installation (Legacy / LuCI Version)

If you prefer to manually install the LuCI-based version (older), follow these steps:

### 1. File Deployment
You need to transfer the files from this project to your OpenWrt router. You can use **WinSCP** or **SCP**.

### Map local files to router paths:

| Local Path | Router Path | Description |
|------------|-------------|-------------|
| `luasrc/controller/pisowifi.lua` | `/usr/lib/lua/luci/controller/pisowifi.lua` | Main Controller & API |
| `luasrc/view/pisowifi/index.htm` | `/usr/lib/lua/luci/view/pisowifi/index.htm` | Captive Portal Landing Page |
| `luasrc/view/pisowifi/admin.htm` | `/usr/lib/lua/luci/view/pisowifi/admin.htm` | Admin Dashboard |
| `luasrc/model/cbi/pisowifi/settings.lua` | `/usr/lib/lua/luci/model/cbi/pisowifi/settings.lua` | Settings Model |
| `root/usr/bin/pisowifi_firewall.sh` | `/usr/bin/pisowifi_firewall.sh` | Firewall/Captive Portal Script |
| `root/etc/config/pisowifi` | `/etc/config/pisowifi` | Configuration File |
| `root/etc/rc.button/wps` | `/etc/rc.button/wps` | WPS Button Script (Coin Insert) |
| `luci-static/resources/pisowifi.css` | `/www/luci-static/resources/pisowifi.css` | Stylesheet |
| `index.html` | `/www/index.html` | Redirect to Portal |

## 2. Permissions & Setup
After copying the files, SSH into your router and run:

```sh
# Make the WPS button script executable
chmod +x /etc/rc.button/wps

# Ensure the coin counter file exists and is writable
touch /tmp/pisowifi_coins
chmod 777 /tmp/pisowifi_coins

# Clear LuCI cache to load new controller
rm -rf /tmp/luci-modulecache/
rm -f /tmp/luci-indexcache
```

## 3. Network & WiFi Configuration
Ensure your router's LAN IP is set to **10.0.0.1** and WiFi is open with SSID **NEXI-FI PISOWIFI**.
You can do this by copying and running the provided script `setup_network.sh`:

1.  Copy `setup_network.sh` to `/tmp/setup_network.sh` on your router.
2.  Make it executable: `chmod +x /tmp/setup_network.sh`
3.  Run it: `/tmp/setup_network.sh`

This script will:
*   Set LAN IP to `10.0.0.1`.
*   Enable WiFi radio (`radio0`).
*   Set SSID to `NEXI-FI PISOWIFI`.
*   Set Encryption to `none` (Open).
*   Attach WiFi to LAN network.

Alternatively, you can manually edit `/etc/config/network` and `/etc/config/wireless`.
```
config interface 'lan'
    option ipaddr '10.0.0.1'
    ...
```
And restart network: `/etc/init.d/network restart`

## 4. Accessing the PisoWifi

### **Client / User View (Captive Portal)**
*   **URL:** `http://10.0.0.1/` (or `http://10.0.0.1/cgi-bin/luci/pisowifi`)
*   **How to use:**
    1.  Connect to the Wi-Fi.
    2.  Go to `http://10.0.0.1`.
    3.  Click **"INSERT COIN"**.
    4.  Press the **WPS Button** on your router. (1 Press = 1 Peso).
    5.  Click **"Done & Start Internet"**.

### **Admin Dashboard**
*   **URL:** `http://10.0.0.1/cgi-bin/luci/admin/pisowifi/dashboard`
*   **Login:** Use your router's root password (default LuCI login).
*   **Features:**
    *   View System Status.
    *   See Active Users (MAC, Time Remaining).
    *   Kick Users.

## 5. Troubleshooting
*   **Iptables Error:** If `iptables` commands fail, install the compatibility layer:
    `opkg update && opkg install iptables-nft`
*   **Button not working:** Check system logs (`logread -f`) while pressing the button to see if "Coin inserted" logs appear.
