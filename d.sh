#!/bin/bash

# =================================================================
# BEÁLLÍTÁSOK - A $172.16.50.0/25$ HÁLÓZATHOZ IGAZÍTVA
# =================================================================
XXX="50"                        # A te azonosítód
NETWORK_PREFIX="172.16.$XXX"    # 172.16.50
INTERFACE="ens33"               # A hálózati kártya neve
# A szerver címe (utolsó előtti): .125
# A tűzfal címe (utolsó): .126
# =================================================================

# Színek
ZOLD='\033[0;32m'
KEK='\033[0;34m'
NC='\033[0m'

case_3() {
    echo -e "${KEK}[3. Feladat] DHCP telepítése (172.16.50.0/25)...${NC}"
    sudo apt update && sudo apt install -y isc-dhcp-server
    
    # DHCP Konfiguráció
    cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf
subnet ${NETWORK_PREFIX}.0 netmask 255.255.255.128 {
  range ${NETWORK_PREFIX}.1 ${NETWORK_PREFIX}.30;
  option routers ${NETWORK_PREFIX}.126;
  option domain-name-servers ${NETWORK_PREFIX}.125;
  default-lease-time 600;
  max-lease-time 7200;
}

host windows-client {
  # Cseréld ki a MAC címet a Windows gépére a teszt előtt!
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
    sudo mkdir -p /srv/megosztas
    sudo chmod 777 /srv/megosztas
    if ! grep -q "/srv/megosztas" /etc/exports; then
        echo "/srv/megosztas *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
    fi
    sudo exportfs -a
    sudo systemctl restart nfs-kernel-server
    echo -e "${ZOLD}NFS kész! Csatolás kliensen: mount ${NETWORK_PREFIX}.125:/srv/megosztas /mnt${NC}"
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
    echo -e "${ZOLD}Adj meg jelszót a Samba user2-nek!${NC}"
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
    echo -e "${ZOLD}SAMBA kész! Elérés Windowsról: \\\\${NETWORK_PREFIX}.125\\${NC}"
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
    echo -e "${ZOLD}Web kész! Elérés: http://${NETWORK_PREFIX}.125${NC}"
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
    echo -e "${ZOLD}FTP kész! user2 a saját mappájába van zárva.${NC}"
}

case_9() {
    echo -e "${KEK}[9. Feladat] SSH port 6789...${NC}"
    sudo sed -i 's/#Port 22/Port 6789/g' /etc/ssh/sshd_config
    sudo sed -i 's/Port 22/Port 6789/g' /etc/ssh/sshd_config
    sudo systemctl restart ssh
    echo -e "${ZOLD}SSH kész! Port: 6789${NC}"
}

# Főmenü
while true; do
    echo -e "\nZH MEGOLDÓ - IP: ${NETWORK_PREFIX}.125"
    echo "3. DHCP | 5. NFS | 6. SAMBA | 7. WEB | 8. FTP | 9. SSH | q. Kilépés"
    read -p "Válassz: " opt
    case $opt in
        3) case_3 ;;
        5) case_5 ;;
        6) case_6 ;;
        7) case_7 ;;
        8) case_8 ;;
        9) case_9 ;;
        q) exit 0 ;;
        *) echo "Hibás opció!" ;;
    esac
done