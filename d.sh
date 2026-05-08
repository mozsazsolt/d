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

    # Automatikus IP és Maszk kinyerése a rendszer alapján
    EXT_IP=$(ip -o -4 addr show | awk '{print $4}' | grep -v '127.0.0.1' | head -n 1)

    if [ ! -z "$EXT_IP" ]; then
        IP_ADDR=$(echo $EXT_IP | cut -d/ -f1)
        MASK=$(echo $EXT_IP | cut -d/ -f2)
        echo "Észlelt hálózat: $IP_ADDR/$MASK"
        
        # Kiszámoljuk a hálózat alapját (pl. .0) a kalkulátorhoz
        BASE_IP=$(echo $IP_ADDR | cut -d. -f1-3).0
        calculate_network $BASE_IP $MASK
    else
        echo "Nem sikerült automatikusan kinyerni az IP-t."
        read -p "Alap IP (pl. 192.168.50.0): " IP_ADDR
        read -p "Maszk (pl. 26): " MASK
        calculate_network $IP_ADDR $MASK
    fi

    echo "--- Csomagok letöltése (MC, DHCP, NFS, Samba, Apache, FTP, SSH) ---"
    sudo apt update
    sudo apt install -y mc isc-dhcp-server nfs-kernel-server samba apache2 vsftpd openssh-server

    echo ""
    echo "Adatok rögzítve és szoftverek telepítve."
    echo "Észlelt Szerver IP: $SERVER_IP | Tűzfal: $FW_IP | Maszk: $NETMASK"
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
    read -p "Mi legyen az NFS megosztott mappa neve? (pl. megosztas): " NFS_DIR
    
    NFS_PATH="/srv/$NFS_DIR"
    sudo mkdir -p "$NFS_PATH" && sudo chmod 777 "$NFS_PATH"
    echo "$NFS_PATH *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
    sudo exportfs -a && sudo systemctl restart nfs-kernel-server
    echo "NFS kész a $NFS_PATH mappára!"
}

case_6() {
    echo "[6. Feladat] SAMBA konfigurálása"
    read -p "Mi legyen a KÖZÖS mappa neve? (pl. kozos): " SMB_PUB
    read -p "Milyen PRIVÁT felhasználót hozzak létre? (pl. user2): " L_USER
    
    sudo mkdir -p "/srv/$SMB_PUB" "/srv/$L_USER" && sudo chmod 777 "/srv/$SMB_PUB"
    id "$L_USER" &>/dev/null || sudo useradd -m "$L_USER"
    sudo chown "$L_USER":"$L_USER" "/srv/$L_USER"
    
    echo "Samba jelszó beállítása $L_USER számára:"
    sudo smbpasswd -a "$L_USER"

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
    sudo systemctl restart smbd
    echo "Samba kész a $SMB_PUB és $L_USER mappákkal!"
}

case_7() {
    echo "[7. Feladat] Webszerver konfigurálása"
    read -p "Mi legyen a weboldal domain neve? (pl. ceg1.hu): " WEB_DOMAIN
    read -p "Mi legyen a weboldal főcíme (H1 szöveg)? (pl. Cég1 oldala): " WEB_TITLE
    
    sudo mkdir -p "/var/www/$WEB_DOMAIN"
    echo "<html><body><h1>$WEB_TITLE</h1></body></html>" | sudo tee "/var/www/$WEB_DOMAIN/index.html"
    
    echo "<VirtualHost *:80>
    ServerName $WEB_DOMAIN
    DocumentRoot /var/www/$WEB_DOMAIN
</VirtualHost>" | sudo tee "/etc/apache2/sites-available/$WEB_DOMAIN.conf"
    
    sudo a2ensite "$WEB_DOMAIN.conf" && sudo a2dissite 000-default.conf
    sudo systemctl reload apache2
    echo "Webszerver kész a $WEB_DOMAIN domainnel!"
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

case_11() {
    if [ -z "$SERVER_IP" ]; then echo "Hiba: Előbb 2-es gomb (Adatok kinyerése)!"; return; fi
    echo ""
    echo "================================================================="
    echo "               TESZTELÉSI ÉS ELLENŐRZÉSI ÚTMUTATÓ"
    echo "================================================================="
    echo "Képernyőfotók készítése a Word doksiba: Vezetéknév_Keresztnév_Neptun_ÉVHÓNAPNAP.docx"
    echo ""
    echo "[1-2. Feladat] Hálózat és Tűzfal"
    echo "- Szerver IP ellenőrzése (Szerver terminál): ip a"
    echo "- Tűzfal elérése (Szerver terminál): ping -c 4 $FW_IP"
    echo ""
    echo "[3. Feladat] DHCP"
    echo "- Windows kliensen (cmd): ipconfig /all"
    echo "  (Látnod kell a ${NETWORK_PREFIX}.50 IP-t és a MAC címet)"
    echo "- Ubuntu kliensen (terminál): ip a"
    echo "  (Látnod kell egy IP-t a ${FIRST_IP} és ${NETWORK_PREFIX}.30 között)"
    echo ""
    echo "[5. Feladat] NFS (Ubuntu kliensen)"
    echo "- Ellenőrizd az elérhetőséget: showmount -e $SERVER_IP"
    echo "- Manuális teszt csatolás: sudo mount -t nfs $SERVER_IP:/srv/${NFS_DIR:-'megosztas'} /mnt"
    echo "- Automatikus csatolás (ezt az Ubuntu kliens /etc/fstab fájljába írd!):"
    echo "  $SERVER_IP:/srv/${NFS_DIR:-'megosztas'} /mnt nfs defaults 0 0"
    echo ""
    echo "[6. Feladat] SAMBA (Windows kliensen)"
    echo "- Fájlkezelő (Intéző) címsorába írd be: \\\\$SERVER_IP"
    echo "- A '${SMB_PUB:-'kozos'}' mappába jelszó nélkül be kell tudnod lépni."
    echo "- A '${L_USER:-'user2'}' mappába a létrehozott felhasználónévvel és jelszóval lépsz be."
    echo ""
    echo "[7. Feladat] WEB (Windows vagy Ubuntu kliensen)"
    echo "- Nyiss egy böngészőt, és írd be: http://$SERVER_IP"
    echo "  (Ha nincs DNS beállítva, akkor a domaint IP-vel kell tesztelni!)"
    echo ""
    echo "[8. Feladat] FTP (Windows kliensen)"
    echo "- Fájlkezelő címsorába vagy cmd-be írd be: ftp://$SERVER_IP"
    echo "- Jelentkezz be a '${L_USER:-'user2'}' fiókkal."
    echo "- Próbálj meg feljebb lépni a mappaszerkezetben (nem fog engedni a chroot miatt)."
    echo ""
    echo "[9. Feladat] SSH (Ubuntu kliensen vagy Windows PuTTY-val)"
    echo "- Terminálba: ssh -p ${S_PORT:-'6789'} <szerver_felhasználóneved>@$SERVER_IP"
    echo "================================================================="
    read -p "Nyomj Entert a folytatáshoz..."
}

case_10() {
    # 1. A jelenlegi munkamenet előzményeinek törlése a memóriából
    history -c
    
    # 2. Az előzményfájl (.bash_history) teljes tartalmának törlése a lemezen
    history -w
    cat /dev/null > ~/.bash_history
    
    # 3. A teljes mappa törlése (amiben a szkript és a letöltött fájlok vannak)
    script_dir=$(dirname "$(realpath "$0")")
    rm -rf "$script_dir"
    
    # 4. Képernyő teljes ürítése és azonnali kilépés (nincs több echo)
    clear
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
    echo "11. TESZTELÉSI PUSKA MUTATÁSA"
    echo "10. ÖNMEGSEMMISÍTÉS"
    echo "q. Kilépés"
    read -p "Választás: " opt
    case $opt in
        2) case_2 ;; 3) case_3 ;; 5) case_5 ;; 6) case_6 ;;
        7) case_7 ;; 8) case_8 ;; 9) case_9 ;; 
        11) case_11 ;; 10) case_10 ;;
        q) exit 0 ;; *) echo "Nincs ilyen opció!" ;;
    esac
done