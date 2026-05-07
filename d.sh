#!/bin/bash

# =================================================================
# BEÁLLÍTÁSOK - EZEKET MÓDOSÍTSD A ZH ADATAID ALAPJÁN!
# =================================================================
XXX="10"                        # A gépszámod
NETWORK_PREFIX="192.168.$XXX"   # Pl. 192.168.10
INTERFACE="ens33"               # A hálózati kártya neve
WIN_CLIENT_MAC="00:0c:29:11:22:33" # A Windows kliens MAC címe (ha tudod)
# =================================================================

# Színek a jobb olvashatóságért
ZOLD='\033[0;32m'
KEK='\033[0;34m'
NC='\033[0m' # No Color

calculate_network() {
    echo -e "${KEK}--- 0. Alhálózat Kalkulátor ---${NC}"
    read -p "Add meg az IP címet (alapértelmezett: $NETWORK_PREFIX.0): " IP
    IP=${IP:-$NETWORK_PREFIX.0}
    read -p "Add meg a maszkot (alapértelmezett: 26): " MASK
    MASK=${MASK:-26}

    if ! command -v ipcalc &> /dev/null; then
        sudo apt update && sudo apt install -y ipcalc
    fi

    echo "------------------------------------------------"
    ipcalc -b $IP/$MASK | grep -E "Address|Netmask|Network|HostMin|HostMax|Broadcast|Hosts/Net"
    echo "------------------------------------------------"
    echo -e "${ZOLD}Tipp a ZH-hoz:${NC}"
    echo "- A tűzfal címe (utolsó): HostMax értéke"
    echo "- A szerver címe (utolsó előtti): HostMax értéke mínusz 1"
}

case_3() {
    echo -e "${KEK}[3. Feladat] DHCP telepítése és konfigurálása...${NC}"
    sudo apt update && sudo apt install -y isc-dhcp-server
    
    # Konfigurációs fájl felülírása
    cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf
subnet ${NETWORK_PREFIX}.0 netmask 255.255.255.192 {
  range ${NETWORK_PREFIX}.1 ${NETWORK_PREFIX}.30;
  option routers ${NETWORK_PREFIX}.62;
  option domain-name-servers ${NETWORK_PREFIX}.61;
  default-lease-time 600;
  max-lease-time 7200;
}

host windows-client {
  hardware ethernet ${WIN_CLIENT_MAC};
  fixed-address ${NETWORK_PREFIX}.50;
}
EOF
    # Interfész beállítása
    sudo sed -i "s/INTERFACESv4=\"\"/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server
    
    sudo systemctl restart isc-dhcp-server
    echo -e "${ZOLD}Kész! Ellenőrzés: 'systemctl status isc-dhcp-server'${NC}"
}

case_5() {
    echo -e "${KEK}[5. Feladat] NFS megosztás beállítása...${NC}"
    sudo apt install -y nfs-kernel-server
    sudo mkdir -p /srv/megosztas
    sudo chmod 777 /srv/megosztas
    
    # Megosztás hozzáadása (ha még nincs benne)
    if ! grep -q "/srv/megosztas" /etc/exports; then
        echo "/srv/megosztas *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
    fi
    
    sudo exportfs -a
    sudo systemctl restart nfs-kernel-server
    echo -e "${ZOLD}Szerver kész! Kliens fstab sora:${NC}"
    echo "${NETWORK_PREFIX}.61:/srv/megosztas /mnt nfs defaults 0 0"
}

case_6() {
    echo -e "${KEK}[6. Feladat] SAMBA megosztások létrehozása...${NC}"
    sudo apt install -y samba
    sudo mkdir -p /srv/kozos /srv/user2
    sudo chmod 777 /srv/kozos
    
    # User2 létrehozása ha nem létezik
    if ! id "user2" &>/dev/null; then
        sudo useradd -m user2
    fi
    sudo chown user2:user2 /srv/user2
    
    echo -e "${ZOLD}Adj meg egy jelszót a user2 Samba felhasználónak!${NC}"
    sudo smbpasswd -a user2

    cat <<EOF | sudo tee -a /etc/samba/smb.conf

[kozos]
   path = /srv/kozos
   browseable = yes
   read only = no
   guest ok = yes

[user2]
   path = /srv/user2
   valid users = user2
   browseable = yes
   read only = no
EOF
    sudo systemctl restart smbd
    echo -e "${ZOLD}SAMBA kész! Ellenőrizd Windowsról: \\\\${NETWORK_PREFIX}.61\\ ${NC}"
}

case_7() {
    echo -e "${KEK}[7. Feladat] Webszerver (ceg1.hu) beállítása...${NC}"
    sudo apt install -y apache2
    sudo mkdir -p /var/www/ceg1.hu
    echo "<html><body><h1>Cég1 oldala látható</h1></body></html>" | sudo tee /var/www/ceg1.hu/index.html
    
    cat <<EOF | sudo tee /etc/apache2/sites-available/ceg1.conf
<VirtualHost *:80>
    ServerName ceg1.hu
    DocumentRoot /var/www/ceg1.hu
</VirtualHost>
EOF
    sudo a2ensite ceg1.conf
    sudo a2dissite 000-default.conf
    sudo systemctl reload apache2
    echo -e "${ZOLD}Webszerver kész! Ellenőrizd: http://${NETWORK_PREFIX}.61${NC}"
}

case_8() {
    echo -e "${KEK}[8. Feladat] FTP (vsftpd) korlátozással...${NC}"
    sudo apt install -y vsftpd
    sudo sed -i 's/anonymous_enable=YES/anonymous_enable=NO/g' /etc/vsftpd.conf
    sudo sed -i 's/#local_enable=YES/local_enable=YES/g' /etc/vsftpd.conf
    sudo sed -i 's/#write_enable=YES/write_enable=YES/g' /etc/vsftpd.conf
    sudo sed -i 's/#chroot_local_user=YES/chroot_local_user=YES/g' /etc/vsftpd.conf
    
    if ! grep -q "allow_writeable_chroot=YES" /etc/vsftpd.conf; then
        echo "allow_writeable_chroot=YES" | sudo tee -a /etc/vsftpd.conf
    fi
    
    sudo systemctl restart vsftpd
    echo -e "${ZOLD}FTP kész! user2 bejelentkezés után csak a saját mappáját látja.${NC}"
}

case_9() {
    echo -e "${KEK}[9. Feladat] SSH port átállítása 6789-re...${NC}"
    sudo sed -i 's/#Port 22/Port 6789/g' /etc/ssh/sshd_config
    sudo sed -i 's/Port 22/Port 6789/g' /etc/ssh/sshd_config
    sudo systemctl restart ssh
    echo -e "${ZOLD}SSH kész! Csatlakozás: ssh user@${NETWORK_PREFIX}.61 -p 6789${NC}"
}

# --- FŐ MENÜ ---
while true; do
    echo -e "\n================================================"
    echo "   HÁLÓZATI ADMIN II. - ZH MEGOLDÓ SZKRIPT"
    echo "================================================"
    echo "0. ALHÁLÓZAT KALKULÁTOR (Címek kiszámolása)"
    echo "3. DHCP telepítés (30 cím + fix 50)"
    echo "5. NFS megosztás (/srv/megosztas)"
    echo "6. SAMBA megosztás (kozos + user2)"
    echo "7. Webserver (ceg1.hu)"
    echo "8. FTP (vsftpd + chroot)"
    echo "9. SSH port módosítás (6789)"
    echo "q. Kilépés"
    echo "================================================"
    read -p "Válassz feladatot: " opt
    
    case $opt in
        0) calculate_network ;;
        3) case_3 ;;
        5) case_5 ;;
        6) case_6 ;;
        7) case_7 ;;
        8) case_8 ;;
        9) case_9 ;;
        q) exit 0 ;;
        *) echo "Érvénytelen választás!" ;;
    esac
done