#!/bin/bash

# =================================================================
# GLOBÁLIS VÁLTOZÓK (A 2. menüpont tölti fel)
# =================================================================
XXX=""
MASK=""
NETWORK_PREFIX=""
NETMASK=""
SERVER_IP=""
FW_IP=""
INTERFACE="ens33"

# Színek a jobb olvashatóságért
ZOLD='\033[0;32m'
KEK='\033[0;34m'
SARGA='\033[1;33m'
PIROS='\033[0;31m'
NC='\033[0m'

# =================================================================
# FUNKCIÓK
# =================================================================

case_2() {
    echo -e "${KEK}[2. Feladat] Adatok megadása és számítás${NC}"
    read -p "Add meg az XXX értéket (pl. 50): " XXX
    read -p "Add meg a maszkot (25 vagy 26): " MASK
    
    NETWORK_PREFIX="192.168.$XXX"
    
    if [ "$MASK" -eq 26 ]; then
        NETMASK="255.255.255.192"
        FIRST_IP="${NETWORK_PREFIX}.1"
        SERVER_IP="${NETWORK_PREFIX}.61"
        FW_IP="${NETWORK_PREFIX}.62"
        LAST_IP="${NETWORK_PREFIX}.62"
    elif [ "$MASK" -eq 25 ]; then
        NETMASK="255.255.255.128"
        FIRST_IP="${NETWORK_PREFIX}.1"
        SERVER_IP="${NETWORK_PREFIX}.125"
        FW_IP="${NETWORK_PREFIX}.126"
        LAST_IP="${NETWORK_PREFIX}.126"
    else
        echo -e "${PIROS}Hiba: Csak 25 vagy 26 maszkot tudok számolni!${NC}"
        return
    fi

    echo -e "\n${ZOLD}SZÁMÍTOTT ÉRTÉKEK A DOKUMENTÁCIÓHOZ:${NC}"
    echo "-------------------------------------------------------"
    echo -e "Hálózat:          ${SARGA}${NETWORK_PREFIX}.0 / $MASK${NC}"
    echo -e "Netmask:          $NETMASK"
    echo -e "Első osztható IP: ${SARGA}$FIRST_IP${NC} (DHCP tartomány eleje)"
    echo -e "Szerver IP:       ${SARGA}$SERVER_IP${NC} (Utolsó előtti cím)"
    echo -e "Tűzfal/GW IP:     ${SARGA}$FW_IP${NC} (Utolsó cím)"
    echo "-------------------------------------------------------"
}

case_3() {
    if [ -z "$XXX" ]; then echo -e "${PIROS}Hiba: Előbb a 2-es gombbal add meg az adatokat!${NC}"; return; fi
    echo -e "${KEK}[3. Feladat] DHCP telepítése...${NC}"
    sudo apt update && sudo apt install -y isc-dhcp-server
    
    cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf
subnet ${NETWORK_PREFIX}.0 netmask $NETMASK {
  range ${NETWORK_PREFIX}.1 ${NETWORK_PREFIX}.30;
  option routers $FW_IP;
  option domain-name-servers $SERVER_IP;
  default-lease-time 600;
  max-lease-time 7200;
}

host windows-client {
  # Itt írd át a MAC címet a saját Windowsodéra!
  hardware ethernet 00:0c:29:11:22:33;
  fixed-address ${NETWORK_PREFIX}.50;
}
EOF
    sudo sed -i "s/INTERFACESv4=\"\"/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server
    sudo systemctl restart isc-dhcp-server
    echo -e "${ZOLD}DHCP kész!${NC}"
}

case_5() {
    echo -e "${KEK}[5. Feladat] NFS megosztás...${NC}"
    sudo apt install -y nfs-kernel-server
    sudo mkdir -p /srv/megosztas
    sudo chmod 777 /srv/megosztas
    if ! grep -q "/srv/megosztas" /etc/exports; then
        echo "/srv/megosztas *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
    fi
    sudo exportfs -a
    sudo systemctl restart nfs-kernel-server
    echo -e "${ZOLD}NFS kész! Csatolás kliensen: mount $SERVER_IP:/srv/megosztas /mnt${NC}"
}

case_6() {
    echo -e "${KEK}[6. Feladat] SAMBA (kozos + user2)...${NC}"
    sudo apt install -y samba
    sudo mkdir -p /srv/kozos /srv/user2
    sudo chmod 777 /srv/kozos
    if ! id "user2" &>/dev/null; then
        sudo useradd -m user2
    fi
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
    echo -e "${ZOLD}SAMBA kész! Elérés Windowsról: \\\\$SERVER_IP\\${NC}"
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
    sudo a2ensite ceg1.conf
    sudo a2dissite 000-default.conf
    sudo systemctl reload apache2
    echo -e "${ZOLD}Web kész! Elérés: http://$SERVER_IP${NC}"
}

case_8() {
    echo -e "${KEK}[8. Feladat] FTP (vsftpd + user2 korlátozás)...${NC}"
    sudo apt install -y vsftpd
    sudo sed -i 's/anonymous_enable=YES/anonymous_enable=NO/g' /etc/vsftpd.conf
    sudo sed -i 's/#local_enable=YES/local_enable=YES/g' /etc/vsftpd.conf
    sudo sed -i 's/#write_enable=YES/write_enable=YES/g' /etc/vsftpd.conf
    sudo sed -i 's/#chroot_local_user=YES/chroot_local_user=YES/g' /etc/vsftpd.conf
    echo "allow_writeable_chroot=YES" | sudo tee -a /etc/vsftpd.conf
    sudo systemctl restart vsftpd
    echo -e "${ZOLD}FTP kész! user2 korlátozva.${NC}"
}

case_9() {
    echo -e "${KEK}[9. Feladat] SSH port 6789...${NC}"
    sudo sed -i 's/#Port 22/Port 6789/g' /etc/ssh/sshd_config
    sudo sed -i 's/Port 22/Port 6789/g' /etc/ssh/sshd_config
    sudo systemctl restart ssh
    echo -e "${ZOLD}SSH kész! Port: 6789${NC}"
}

case_10() {
    echo -e "${PIROS}NYOMOK ELTÜNTETÉSE ÉS ÖNMEGSEMMISÍTÉS...${NC}"
    # Bash history törlése a memóriából
    history -c
    # A fájl törlése
    rm -- "$0"
    echo -e "${SARGA}A fájl törölve. Kilépés...${NC}"
    exit 0
}

# =================================================================
# FŐMENÜ
# =================================================================

while true; do
    echo -e "\n${KEK}===================================================${NC}"
    echo -e "${SARGA}   MINTA ZH MEGOLDÓ - IP: ${SERVER_IP:-'NINCS'} ${NC}"
    echo -e "${KEK}===================================================${NC}"
    echo "2. ADATOK MEGADÁSA ÉS SZÁMÍTÁSA (Kezdd ezzel!)"
    echo "3. DHCP | 5. NFS | 6. SAMBA | 7. WEB | 8. FTP | 9. SSH"
    echo "10. ÖNMEGSEMMISÍTÉS (Szkript törlése)"
    echo "q. Kilépés"
    echo "---------------------------------------------------"
    read -p "Válassz: " opt
    case $opt in
        2) case_2 ;;
        3) case_3 ;;
        5) case_5 ;;
        6) case_6 ;;
        7) case_7 ;;
        8) case_8 ;;
        9) case_9 ;;
        10) case_10 ;;
        q) exit 0 ;;
        *) echo -e "${PIROS}Hibás opció!${NC}" ;;
    esac
done