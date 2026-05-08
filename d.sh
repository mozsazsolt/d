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
    echo "[2. Feladat] Adatok kinyerése és szoftverek letöltése"

    EXT_IP=$(ip -o -4 addr show | awk '{print $4}' | grep -v '127.0.0.1' | head -n 1)
    EXT_GW=$(ip route show default | awk '{print $3}' | head -n 1)

    if [ ! -z "$EXT_IP" ]; then
        IP_ADDR=$(echo $EXT_IP | cut -d/ -f1)
        MASK=$(echo $EXT_IP | cut -d/ -f2)
        BASE_IP=$(echo $IP_ADDR | cut -d. -f1-3).0
        calculate_network $BASE_IP $MASK
        SERVER_IP="$IP_ADDR"
        if [ ! -z "$EXT_GW" ]; then FW_IP="$EXT_GW"; fi
        if [ "$FW_IP" == "$FIRST_IP" ]; then
            LAST_OCTET=$(echo $FIRST_IP | cut -d. -f4)
            FIRST_IP="${NETWORK_PREFIX}.$((LAST_OCTET + 1))"
        fi
        echo "Észlelt Szerver IP: $SERVER_IP/$MASK"
        echo "Észlelt Tűzfal (Router) IP: $FW_IP"
    else
        echo "Hiba: Nem találtam beállított IP-t!"
        read -p "Add meg manuálisan az alap IP-t: " IP_ADDR
        read -p "Add meg a Maszkot (pl. 26): " MASK
        calculate_network $IP_ADDR $MASK
    fi

    echo "--- Csomagok letöltése ---"
    sudo apt update
    sudo apt install -y mc isc-dhcp-server bind9 bind9utils bind9-doc nfs-kernel-server samba apache2 vsftpd openssh-server

    echo "Szerver: $SERVER_IP | Tűzfal: $FW_IP | Maszk: $NETMASK"
}

case_3() {
    if [ -z "$SERVER_IP" ]; then echo "Hiba: Előbb 2-es gomb!"; return; fi
    echo "[3. Feladat] DHCP konfigurálása"
    DEF_START=$(echo $FIRST_IP | cut -d. -f4)
    read -p "DHCP tartomány kezdete (.X) [$DEF_START]: " IN_START
    OCTET_START=${IN_START:-$DEF_START}
    DHCP_START="${NETWORK_PREFIX}.${OCTET_START}"
    read -p "DHCP tartomány vége (.X) [30]: " IN_END
    OCTET_END=${IN_END:-30}
    DHCP_END="${NETWORK_PREFIX}.${OCTET_END}"
    read -p "Windows kliens fix IP-je (.X) [50]: " IN_WIN
    OCTET_WIN=${IN_WIN:-50}
    WIN_IP="${NETWORK_PREFIX}.${OCTET_WIN}"
    read -p "Windows kliens MAC címe (kötelező): " WIN_MAC
    
    cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf
subnet ${NETWORK_PREFIX}.0 netmask $NETMASK {
  range $DHCP_START $DHCP_END;
  option routers $FW_IP;
  option domain-name-servers $SERVER_IP;
  default-lease-time 600;
  max-lease-time 7200;
}
host windows-client {
  hardware ethernet $WIN_MAC;
  fixed-address $WIN_IP;
}
EOF
    sudo sed -i "s/INTERFACESv4=\"\"/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server
    sudo systemctl restart isc-dhcp-server
    echo "DHCP kész!"
}

case_4() {
    if [ -z "$SERVER_IP" ]; then echo "Hiba: Előbb 2-es gomb!"; return; fi
    echo "[4. Feladat] DNS (BIND9) konfigurálása"
    read -p "Mi legyen a DNS zóna neve? [gyakorlo.local]: " IN_ZONE [cite: 14, 15]
    DNS_ZONE=${IN_ZONE:-"gyakorlo.local"} [cite: 15]
    
    # Fordított zóna hálózati része és szerver utolsó oktettje
    REV_NET=$(echo $SERVER_IP | awk -F. '{print $3"."$2"."$1}')
    SRV_OCTET=$(echo $SERVER_IP | cut -d. -f4)

    # 1. Options
    cat <<EOF | sudo tee /etc/bind/named.conf.options
options {
    directory "/var/cache/bind";
    forwarders { 8.8.8.8; 8.8.4.4; };
    dnssec-validation auto;
    listen-on-v6 { any; };
};
EOF

    # 2. Zónák definiálása
    cat <<EOF | sudo tee /etc/bind/named.conf.local
zone "$DNS_ZONE" {
    type master;
    file "/etc/bind/db.$DNS_ZONE";
};

zone "${REV_NET}.in-addr.arpa" {
    type master;
    file "/etc/bind/db.rev";
};
EOF

    # 3. Névkeresési zónafájl (Forward) [cite: 14]
    cat <<EOF | sudo tee /etc/bind/db.$DNS_ZONE
\$TTL    604800
@       IN      SOA     ns1.$DNS_ZONE. admin.$DNS_ZONE. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.$DNS_ZONE.
ns1     IN      A       $SERVER_IP
@       IN      A       $SERVER_IP
www     IN      A       $SERVER_IP
EOF

    # 4. Címkeresési zónafájl (Reverse) [cite: 14]
    cat <<EOF | sudo tee /etc/bind/db.rev
\$TTL    604800
@       IN      SOA     ns1.$DNS_ZONE. admin.$DNS_ZONE. (
                              1         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.$DNS_ZONE.
$SRV_OCTET  IN      PTR     ns1.$DNS_ZONE.
$SRV_OCTET  IN      PTR     $DNS_ZONE.
EOF

    sudo systemctl restart bind9
    echo "DNS kész a(z) $DNS_ZONE zónával!"
}

case_5() {
    echo "[5. Feladat] NFS konfigurálása"
    read -p "Mi legyen az NFS megosztott mappa neve? [megosztas]: " NFS_DIR [cite: 16]
    NFS_PATH="/srv/$NFS_DIR" [cite: 16]
    sudo mkdir -p "$NFS_PATH" && sudo chmod 777 "$NFS_PATH" [cite: 16]
    echo "$NFS_PATH *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports [cite: 17]
    sudo exportfs -a && sudo systemctl restart nfs-kernel-server [cite: 17]
    echo "NFS kész a $NFS_PATH mappára!"
}

case_6() {
    echo "[6. Feladat] SAMBA konfigurálása"
    read -p "Mi legyen a KÖZÖS mappa neve? [kozos]: " SMB_PUB [cite: 18]
    read -p "Milyen PRIVÁT felhasználót hozzak létre? [user2]: " L_USER [cite: 18]
    
    sudo mkdir -p "/srv/$SMB_PUB" "/srv/$L_USER" && sudo chmod 777 "/srv/$SMB_PUB" [cite: 18]
    id "$L_USER" &>/dev/null || sudo useradd -m "$L_USER" [cite: 18]
    sudo chown "$L_USER":"$L_USER" "/srv/$L_USER" [cite: 18]
    
    echo "Samba jelszó beállítása $L_USER számára:"
    sudo smbpasswd -a "$L_USER" [cite: 19]

    cat <<EOF | sudo tee -a /etc/samba/smb.conf
[$SMB_PUB]
   path = /srv/$SMB_PUB
   browseable = yes
   read only = no
   guest ok = yes
[$L_USER]
   path = /srv/$L_USER
   valid users = $L_USER
   browseable = yes
   read only = no
EOF
    sudo systemctl restart smbd [cite: 19]
    echo "Samba kész!"
}

case_7() {
    echo "[7. Feladat] Webszerver konfigurálása"
    read -p "Mi legyen a weboldal domain neve? [ceg1.hu]: " WEB_DOMAIN [cite: 20]
    read -p "Mi legyen a weboldal főcíme? [Cég1 oldala]: " WEB_TITLE [cite: 21]
    
    sudo mkdir -p "/var/www/$WEB_DOMAIN" [cite: 20]
    echo "<html><body><h1>$WEB_TITLE</h1></body></html>" | sudo tee "/var/www/$WEB_DOMAIN/index.html" [cite: 20, 21]
    
    echo "<VirtualHost *:80>
    ServerName $WEB_DOMAIN
    DocumentRoot /var/www/$WEB_DOMAIN
</VirtualHost>" | sudo tee "/etc/apache2/sites-available/$WEB_DOMAIN.conf"
    
    sudo a2ensite "$WEB_DOMAIN.conf" && sudo a2dissite 000-default.conf [cite: 21]
    sudo systemctl reload apache2
    echo "Webszerver kész!"
}

case_8() {
    echo "[8. Feladat] FTP konfigurálása (chroot)"
    sudo sed -i 's/anonymous_enable=YES/anonymous_enable=NO/g; s/#local_enable=YES/local_enable=YES/g; s/#write_enable=YES/write_enable=YES/g; s/#chroot_local_user=YES/chroot_local_user=YES/g' /etc/vsftpd.conf [cite: 22]
    echo "allow_writeable_chroot=YES" | sudo tee -a /etc/vsftpd.conf [cite: 22]
    sudo systemctl restart vsftpd
    echo "FTP kész!"
}

case_9() {
    echo "[9. Feladat] SSH Port átállítása"
    read -p "Melyik portot állítsam be? [6789]: " S_PORT [cite: 23]
    sudo sed -i "s/Port 22/Port $S_PORT/g; s/#Port 22/Port $S_PORT/g" /etc/ssh/sshd_config [cite: 23]
    sudo systemctl restart ssh
    echo "SSH kész a(z) $S_PORT porton!"
}

case_11() {
    if [ -z "$SERVER_IP" ]; then echo "Hiba: Előbb 2-es gomb!"; return; fi
    echo "================================================================="
    echo "               TESZTELÉSI ÉS ELLENŐRZÉSI ÚTMUTATÓ"
    echo "================================================================="
    echo "[4. Feladat] DNS ellenőrzése"
    echo "- Névkeresés: nslookup ${DNS_ZONE:-'gyakorlo.local'}"
    echo "- Címkeresés: nslookup $SERVER_IP"
    echo ""
    echo "[5. Feladat] NFS (Kliensen)"
    echo "- Csatolás: sudo mount -t nfs $SERVER_IP:/srv/${NFS_DIR:-'megosztas'} /mnt"
    echo "- Automatikus csatolás (/etc/fstab):"
    echo "  $SERVER_IP:/srv/${NFS_DIR:-'megosztas'} /mnt nfs defaults 0 0"
    echo ""
    echo "[6. Feladat] SAMBA"
    echo "- Intézőbe: \\\\$SERVER_IP"
    echo ""
    echo "[7. Feladat] WEB"
    echo "- Böngészőbe: http://${WEB_DOMAIN:-'ceg1.hu'} (Vagy IP-vel, ha nincs DNS)"
    echo ""
    echo "[8. Feladat] FTP"
    echo "- ftp://$SERVER_IP (Bejelentkezés ${L_USER:-'user2'} fiókkal)"
    echo ""
    echo "[9. Feladat] SSH"
    echo "- ssh -p ${S_PORT:-'6789'} <user>@$SERVER_IP"
    echo "================================================================="
    read -p "Nyomj Entert a folytatáshoz..."
}

case_10() {
    history -c && history -w && cat /dev/null > ~/.bash_history
    script_dir=$(dirname "$(realpath "$0")")
    rm -rf "$script_dir"
    clear && exit 0
}

# =================================================================
# FŐMENÜ
# =================================================================
while true; do
    echo ""
    echo "--- ZH SEGÉD - IP: ${SERVER_IP:-'NINCS'} ---"
    echo "2. ADATOK ÉS TELEPÍTÉS"
    echo "3. DHCP | 4. DNS | 5. NFS | 6. SAMBA | 7. WEB | 8. FTP | 9. SSH"
    echo "11. TESZTELÉSI PUSKA | 10. ÖNMEGSEMMISÍTÉS | q. Kilépés"
    read -p "Választás: " opt
    case $opt in
        2) case_2 ;; 3) case_3 ;; 4) case_4 ;; 5) case_5 ;; 
        6) case_6 ;; 7) case_7 ;; 8) case_8 ;; 9) case_9 ;; 
        11) case_11 ;; 10) case_10 ;; q) exit 0 ;; *) echo "Nincs ilyen opció!" ;;
    esac
done