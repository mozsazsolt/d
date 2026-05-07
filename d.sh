#!/bin/bash

# =================================================================
# GLOBÁLIS VÁLTOZÓK
# =================================================================
IP_ADDR=""
MASK=""
NETWORK_PREFIX=""
NETMASK=""
SERVER_IP=""
FW_IP=""
FIRST_IP=""
INTERFACE="ens33"

# =================================================================
# IP SZÁMÍTÓ MOTOR
# =================================================================
calculate_network() {
    local ip=$1
    local mask=$2
    local full_mask_bin=$(( 0xFFFFFFFF ^ ((1 << (32 - mask)) - 1) ))
    NETMASK="$(( (full_mask_bin >> 24) & 255 )).$(( (full_mask_bin >> 16) & 255 )).$(( (full_mask_bin >> 8) & 255 )).$(( full_mask_bin & 255 ))"
    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
    local ip_bin=$(( (i1 << 24) + (i2 << 16) + (i3 << 8) + i4 ))
    local net_bin=$(( ip_bin & full_mask_bin ))
    local brd_bin=$(( net_bin | ((1 << (32 - mask)) - 1) ))
    
    FW_IP="$(( (brd_bin - 1 >> 24) & 255 )).$(( (brd_bin - 1 >> 16) & 255 )).$(( (brd_bin - 1 >> 8) & 255 )).$(( (brd_bin - 1) & 255 ))"
    SERVER_IP="$(( (brd_bin - 2 >> 24) & 255 )).$(( (brd_bin - 2 >> 16) & 255 )).$(( (brd_bin - 2 >> 8) & 255 )).$(( (brd_bin - 2) & 255 ))"
    FIRST_IP="$(( (net_bin + 1 >> 24) & 255 )).$(( (net_bin + 1 >> 16) & 255 )).$(( (net_bin + 1 >> 8) & 255 )).$(( (net_bin + 1) & 255 ))"
    NETWORK_PREFIX="$(echo $SERVER_IP | cut -d. -f1-3)"
}

# =================================================================
# MENÜPONTOK
# =================================================================

case_2() {
    echo "[2. Feladat] Hálózati adatok és szoftverek letöltése"
    read -p "Alap IP (pl. 192.168.50.0): " IP_ADDR
    read -p "Maszk (pl. 26): " MASK
    calculate_network $IP_ADDR $MASK

    echo "--- Csomagok letöltése (MC, DHCP, NFS, Samba, Apache, FTP, SSH) ---"
    sudo apt update
    sudo apt install -y mc isc-dhcp-server nfs-kernel-server samba apache2 vsftpd openssh-server

    echo ""
    echo "Hálózat kiszámítva és szoftverek telepítve."
    echo "Szerver IP: $SERVER_IP | Tűzfal: $FW_IP | Maszk: $NETMASK"
}

case_3() {
    if [ -z "$SERVER_IP" ]; then echo "Hiba: Előbb 2-es gomb!"; return; fi
    echo "[3. Feladat] DHCP konfigurálása"
    read -p "Add meg a Windows kliens MAC címét: " WIN_MAC
    
    cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf
subnet ${NETWORK_PREFIX}.0 netmask $NETMASK {
  range $FIRST_IP ${NETWORK_PREFIX}.30;
  option routers $FW_IP;
  option domain-name-servers $SERVER_IP;
  default-lease-time 600;
  max-lease-time 7200;
}
host windows-client {
  hardware ethernet $WIN_MAC;
  fixed-address ${NETWORK_PREFIX}.50;
}
EOF
    sudo sed -i "s/INTERFACESv4=\"\"/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server
    sudo systemctl restart isc-dhcp-server
    echo "DHCP kész!"
}

case_5() {
    echo "[5. Feladat] NFS konfigurálása"
    sudo mkdir -p /srv/megosztas && sudo chmod 777 /srv/megosztas
    echo "/srv/megosztas *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
    sudo exportfs -a && sudo systemctl restart nfs-kernel-server
    echo "NFS kész!"
}

case_6() {
    echo "[6. Feladat] SAMBA konfigurálása"
    read -p "Milyen felhasználót hozzak létre? (pl. user2): " L_USER
    sudo mkdir -p /srv/kozos "/srv/$L_USER" && sudo chmod 777 /srv/kozos
    id "$L_USER" &>/dev/null || sudo useradd -m "$L_USER"
    sudo chown "$L_USER":"$L_USER" "/srv/$L_USER"
    echo "Samba jelszó beállítása $L_USER számára:"
    sudo smbpasswd -a "$L_USER"

    cat <<EOF | sudo tee -a /etc/samba/smb.conf
[kozos]
   path = /srv/kozos
   browseable = yes
   read only = no
   guest ok = yes
[$L_USER]
   path = /srv/$L_USER
   valid users = $L_USER
   browseable = yes
   read only = no
EOF
    sudo systemctl restart smbd
    echo "Samba kész!"
}

case_7() {
    echo "[7. Feladat] Webszerver konfigurálása"
    sudo mkdir -p /var/www/ceg1.hu
    echo "<html><body><h1>Cég1 oldala</h1></body></html>" | sudo tee /var/www/ceg1.hu/index.html
    echo "<VirtualHost *:80>
    ServerName ceg1.hu
    DocumentRoot /var/www/ceg1.hu
</VirtualHost>" | sudo tee /etc/apache2/sites-available/ceg1.conf
    sudo a2ensite ceg1.conf && sudo a2dissite 000-default.conf
    sudo systemctl reload apache2
    echo "Webszerver kész!"
}

case_8() {
    echo "[8. Feladat] FTP konfigurálása (chroot)"
    sudo sed -i 's/anonymous_enable=YES/anonymous_enable=NO/g; s/#local_enable=YES/local_enable=YES/g; s/#write_enable=YES/write_enable=YES/g; s/#chroot_local_user=YES/chroot_local_user=YES/g' /etc/vsftpd.conf
    echo "allow_writeable_chroot=YES" | sudo tee -a /etc/vsftpd.conf
    sudo systemctl restart vsftpd
    echo "FTP kész!"
}

case_9() {
    echo "[9. Feladat] SSH Port átállítása"
    read -p "Melyik portot állítsam be? (pl. 6789): " S_PORT
    sudo sed -i "s/Port 22/Port $S_PORT/g; s/#Port 22/Port $S_PORT/g" /etc/ssh/sshd_config
    sudo systemctl restart ssh
    echo "SSH kész a(z) $S_PORT porton!"
}

case_10() {
    echo "ÖNMEGSEMMISÍTÉS ÉS KILÉPÉS..."
    history -c && rm -- "$0"
    exit 0
}

# =================================================================
# FŐMENÜ
# =================================================================
while true; do
    echo ""
    echo "--- ZH SEGÉD - IP: ${SERVER_IP:-'NINCS'} ---"
    echo "2. ADATOK ÉS TELEPÍTÉS"
    echo "3. DHCP | 5. NFS | 6. SAMBA | 7. WEB | 8. FTP | 9. SSH"
    echo "10. ÖNMEGSEMMISÍTÉS"
    echo "q. Kilépés"
    read -p "Választás: " opt
    case $opt in
        2) case_2 ;; 3) case_3 ;; 5) case_5 ;; 6) case_6 ;;
        7) case_7 ;; 8) case_8 ;; 9) case_9 ;; 10) case_10 ;;
        q) exit 0 ;; *) echo "Nincs ilyen opció!" ;;
    esac
done