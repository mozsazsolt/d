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

# Színek a scannelt megjelenéshez
ZOLD='\033[0;32m'
KEK='\033[0;34m'
SARGA='\033[1;33m'
PIROS='\033[0;31m'
NC='\033[0m'

# =================================================================
# SEGÉDFÜGGVÉNY: IP/MASK SZÁMÍTÁS (BINÁRIS MŰVELETEKKEL)
# =================================================================
calculate_network() {
    local ip=$1
    local mask=$2

    # Alhálózati maszk kiszámítása (pl. 26 -> 255.255.255.192)
    local full_mask_bin=$(( 0xFFFFFFFF ^ ((1 << (32 - mask)) - 1) ))
    NETMASK="$(( (full_mask_bin >> 24) & 255 )).$(( (full_mask_bin >> 16) & 255 )).$(( (full_mask_bin >> 8) & 255 )).$(( full_mask_bin & 255 ))"

    # IP felbontása és hálózati cím meghatározása
    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
    local ip_bin=$(( (i1 << 24) + (i2 << 16) + (i3 << 8) + i4 ))
    local net_bin=$(( ip_bin & full_mask_bin ))
    
    # Broadcast cím meghatározása
    local brd_bin=$(( net_bin | ((1 << (32 - mask)) - 1) ))
    
    # Címek kinyerése a ZH szabályai szerint:
    # Tűzfal (FW_IP) = Utolsó használható IP (Broadcast - 1)
    FW_IP="$(( (brd_bin - 1 >> 24) & 255 )).$(( (brd_bin - 1 >> 16) & 255 )).$(( (brd_bin - 1 >> 8) & 255 )).$(( (brd_bin - 1) & 255 ))"
    # Szerver (SERVER_IP) = Utolsó előtti használható IP (Broadcast - 2)
    SERVER_IP="$(( (brd_bin - 2 >> 24) & 255 )).$(( (brd_bin - 2 >> 16) & 255 )).$(( (brd_bin - 2 >> 8) & 255 )).$(( (brd_bin - 2) & 255 ))"
    # Első IP = Hálózati cím + 1
    FIRST_IP="$(( (net_bin + 1 >> 24) & 255 )).$(( (net_bin + 1 >> 16) & 255 )).$(( (net_bin + 1 >> 8) & 255 )).$(( (net_bin + 1) & 255 ))"
    
    NETWORK_PREFIX="$(echo $SERVER_IP | cut -d. -f1-3)"
}

# =================================================================
# MENÜPONTOK
# =================================================================

case_2() {
    echo -e "${KEK}[2. Feladat] Univerzális Adatmegadás${NC}"
    read -p "Add meg az alap IP-t (pl. 192.168.50.0): " IP_ADDR
    read -p "Add meg a maszkot (pl. 24, 25, 26): " MASK
    
    calculate_network $IP_ADDR $MASK

    echo -e "\n${ZOLD}SZÁMÍTOTT ÉRTÉKEK A ZH-HOZ:${NC}"
    echo "-------------------------------------------------------"
    echo -e "Hálózati maszk:   ${SARGA}$NETMASK${NC}"
    echo -e "Első IP:          ${SARGA}$FIRST_IP${NC}"
    echo -e "Szerver (te):     ${SARGA}$SERVER_IP${NC} (Utolsó előtti)"
    echo -e "Tűzfal (átjáró):  ${SARGA}$FW_IP${NC} (Utolsó)"
    echo "-------------------------------------------------------"
}

case_3() {
    if [ -z "$SERVER_IP" ]; then echo -e "${PIROS}Hiba: Előbb használd a 2-es gombot!${NC}"; return; fi
    echo -e "${KEK}[3. Feladat] DHCP telepítése...${NC}"
    sudo apt update && sudo apt install -y isc-dhcp-server
    
    cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf
subnet ${NETWORK_PREFIX}.0 netmask $NETMASK {
  range $FIRST_IP ${NETWORK_PREFIX}.30;
  option routers $FW_IP;
  option domain-name-servers $SERVER_IP;
  default-lease-time 600;
  max-lease-time 7200;
}
host windows-client {
  hardware ethernet 00:0c:29:11:22:33;
  fixed-address ${NETWORK_PREFIX}.50;
}
EOF
    sudo sed -i "s/INTERFACESv4=\"\"/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server
    sudo systemctl restart isc-dhcp-server
    echo -e "${ZOLD}DHCP kész! Ellenőrizd: systemctl status isc-dhcp-server${NC}"
}

case_5() {
    echo -e "${KEK}[5. Feladat] NFS megosztás...${NC}"
    sudo apt install -y nfs-kernel-server
    sudo mkdir -p /srv/megosztas && sudo chmod 777 /srv/megosztas
    if ! grep -q "/srv/megosztas" /etc/exports; then
        echo "/srv/megosztas *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
    fi
    sudo exportfs -a && sudo systemctl restart nfs-kernel-server
    echo -e "${ZOLD}NFS kész! Kliens mount: mount $SERVER_IP:/srv/megosztas /mnt${NC}"
}

case_6() {
    echo -e "${KEK}[6. Feladat] SAMBA (kozos + user2)...${NC}"
    sudo apt install -y samba
    sudo mkdir -p /srv/kozos /srv/user2 && sudo chmod 777 /srv/kozos
    id "user2" &>/dev/null || sudo useradd -m user2
    sudo chown user2:user2 /srv/user2
    echo -e "${SARGA}Adj meg jelszót a Samba user2-nek!${NC}"
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
    echo -e "${ZOLD}SAMBA kész! Elérés: \\\\$SERVER_IP\\${NC}"
}

case_7() {
    echo -e "${KEK}[7. Feladat] Webszerver (ceg1.hu)...${NC}"
    sudo apt install -y apache2
    sudo mkdir -p /var/www/ceg1.hu
    echo "<html><body><h1>Cég1 oldala látható</h1></body></html>" | sudo tee /var/www/ceg1.hu/index.html
    cat <<EOF | sudo tee /etc/apache2/sites-available/ceg1.conf
<VirtualHost *:80>
    ServerName ceg1.hu
    DocumentRoot /var/www/ceg1.hu
</VirtualHost>
EOF
    sudo a2ensite ceg1.conf && sudo a2dissite 000-default.conf
    sudo systemctl reload apache2
    echo -e "${ZOLD}Web kész! Elérés: http://$SERVER_IP${NC}"
}

case_8() {
    echo -e "${KEK}[8. Feladat] FTP (user2 korlátozás)...${NC}"
    sudo apt install -y vsftpd
    sudo sed -i 's/anonymous_enable=YES/anonymous_enable=NO/g; s/#local_enable=YES/local_enable=YES/g; s/#write_enable=YES/write_enable=YES/g; s/#chroot_local_user=YES/chroot_local_user=YES/g' /etc/vsftpd.conf
    echo "allow_writeable_chroot=YES" | sudo tee -a /etc/vsftpd.conf
    sudo systemctl restart vsftpd
    echo -e "${ZOLD}FTP kész! user2 korlátozva a saját mappájába.${NC}"
}

case_9() {
    echo -e "${KEK}[9. Feladat] SSH port 6789...${NC}"
    sudo sed -i 's/#Port 22/Port 6789/g; s/Port 22/Port 6789/g' /etc/ssh/sshd_config
    sudo systemctl restart ssh
    echo -e "${ZOLD}SSH kész! Port: 6789${NC}"
}

case_10() {
    echo -e "${PIROS}ÖNMEGSEMMISÍTÉS INDÍTVA...${NC}"
    history -c
    rm -- "$0"
    echo -e "${SARGA}Szkript törölve, előzmények ürítve. Kilépés...${NC}"
    exit 0
}

# =================================================================
# FŐMENÜ
# =================================================================

while true; do
    echo -e "\n${SARGA}ZH MEGOLDÓ - Aktuális IP: ${SERVER_IP:-'Nincs megadva'}${NC}"
    echo "2. ADATOK MEGADÁSA ÉS SZÁMÍTÁSA (Kezdd ezzel!)"
    echo "3. DHCP | 5. NFS | 6. SAMBA | 7. WEB | 8. FTP | 9. SSH"
    echo "10. ÖNMEGSEMMISÍTÉS"
    echo "q. Kilépés"
    read -p "Válassz opciót: " opt
    case $opt in
        2) case_2 ;; 3) case_3 ;; 5) case_5 ;; 6) case_6 ;;
        7) case_7 ;; 8) case_8 ;; 9) case_9 ;; 10) case_10 ;;
        q) exit 0 ;;
        *) echo -e "${PIROS}Hibás választás!${NC}" ;;
    esac
done