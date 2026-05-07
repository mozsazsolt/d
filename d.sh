#!/bin/bash

# =================================================================
# GLOBÁLIS VÁLTOZÓK ÉS ALAPÉRTÉKEK
# =================================================================
IP_ADDR=""
MASK=""
NETWORK_PREFIX=""
NETMASK=""
SERVER_IP=""
FW_IP=""
FIRST_IP=""
INTERFACE="ens33"

# Felhasználói adatok (2-es gombbal töltődnek)
USER_NAME="user2"
SSH_PORT="6789"
WIN_MAC=""

# Színek
ZOLD='\033[0;32m'
KEK='\033[0;34m'
SARGA='\033[1;33m'
PIROS='\033[0;31m'
NC='\033[0m'

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
    echo -e "${KEK}[2. Feladat] Adatok és Paraméterek megadása${NC}"
    # Hálózati adatok
    read -p "Alap IP (pl. 192.168.50.0): " IP_ADDR
    read -p "Maszk (pl. 26): " MASK
    calculate_network $IP_ADDR $MASK

    # Egyéb paraméterek
    read -p "Windows gép MAC címe (pl. 00:0c:29:11:22:33): " WIN_MAC
    read -p "Létrehozandó felhasználó neve (alap: user2): " USER_NAME
    USER_NAME=${USER_NAME:-user2}
    read -p "SSH új portja (alap: 6789): " SSH_PORT
    SSH_PORT=${SSH_PORT:-6789}

    echo -e "\n${ZOLD}MINDEN ADAT RÖGZÍTVE ÉS KISZÁMÍTVA!${NC}"
    echo "-------------------------------------------------------"
    echo -e "Szerver IP:    ${SARGA}$SERVER_IP${NC} | Tűzfal: $FW_IP"
    echo -e "Windows MAC:   $WIN_MAC"
    echo -e "Felhasználó:   $USER_NAME"
    echo -e "SSH Port:      $SSH_PORT"
    echo "-------------------------------------------------------"
}

case_3() {
    if [ -z "$WIN_MAC" ]; then echo -e "${PIROS}Hiba: Előbb add meg az adatokat a 2-es gombbal!${NC}"; return; fi
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
  hardware ethernet $WIN_MAC;
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
    sudo mkdir -p /srv/megosztas && sudo chmod 777 /srv/megosztas
    echo "/srv/megosztas *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
    sudo exportfs -a && sudo systemctl restart nfs-kernel-server
}

case_6() {
    echo -e "${KEK}[6. Feladat] SAMBA ($USER_NAME)...${NC}"
    sudo apt install -y samba
    sudo mkdir -p /srv/kozos "/srv/$USER_NAME" && sudo chmod 777 /srv/kozos
    id "$USER_NAME" &>/dev/null || sudo useradd -m "$USER_NAME"
    sudo chown "$USER_NAME":"$USER_NAME" "/srv/$USER_NAME"
    echo -e "${SARGA}Adj meg Samba jelszót a(z) $USER_NAME felhasználónak!${NC}"
    sudo smbpasswd -a "$USER_NAME"

    cat <<EOF | sudo tee -a /etc/samba/smb.conf
[kozos]
   path = /srv/kozos
   browseable = yes
   read only = no
   guest ok = yes
[$USER_NAME]
   path = /srv/$USER_NAME
   valid users = $USER_NAME
   browseable = yes
   read only = no
EOF
    sudo systemctl restart smbd
}

case_7() {
    echo -e "${KEK}[7. Feladat] Webszerver...${NC}"
    sudo apt install -y apache2
    sudo mkdir -p /var/www/ceg1.hu
    echo "<html><body><h1>Cég1 oldala</h1></body></html>" | sudo tee /var/www/ceg1.hu/index.html
    echo "<VirtualHost *:80>
    ServerName ceg1.hu
    DocumentRoot /var/www/ceg1.hu
</VirtualHost>" | sudo tee /etc/apache2/sites-available/ceg1.conf
    sudo a2ensite ceg1.conf && sudo a2dissite 000-default.conf
    sudo systemctl reload apache2
}

case_8() {
    echo -e "${KEK}[8. Feladat] FTP ($USER_NAME korlátozás)...${NC}"
    sudo apt install -y vsftpd
    sudo sed -i 's/anonymous_enable=YES/anonymous_enable=NO/g; s/#local_enable=YES/local_enable=YES/g; s/#write_enable=YES/write_enable=YES/g; s/#chroot_local_user=YES/chroot_local_user=YES/g' /etc/vsftpd.conf
    echo "allow_writeable_chroot=YES" | sudo tee -a /etc/vsftpd.conf
    sudo systemctl restart vsftpd
}

case_9() {
    echo -e "${KEK}[9. Feladat] SSH Port $SSH_PORT...${NC}"
    sudo sed -i "s/Port 22/Port $SSH_PORT/g; s/#Port 22/Port $SSH_PORT/g" /etc/ssh/sshd_config
    sudo systemctl restart ssh
}

case_10() {
    echo -e "${PIROS}ÖNMEGSEMMISÍTÉS...${NC}"
    history -c && rm -- "$0"
    exit 0
}

# =================================================================
# FŐMENÜ
# =================================================================
while true; do
    echo -e "\n${SARGA}ZH MEGOLDÓ - Felhasználó: $USER_NAME | IP: ${SERVER_IP:-'NINCS'}${NC}"
    echo "2. ADATOK MEGADÁSA (Ezzel kezdj!)"
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