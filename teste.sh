#!/bin/bash
#credits to @BasRaayman and @inchenzo

INTERFACE="tun0"
DEFAULT_NET="10.8.0.0/24"
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

while getopts "a:" opt; do
  case $opt in
    a) action=$OPTARG ;;
    *) echo 'Not a valid command' >&2
       exit 1
  esac
done

reset_ip_tables () {
  sudo service iptables restart

  #reset iptables to default
  sudo iptables -P INPUT ACCEPT
  sudo iptables -P FORWARD ACCEPT
  sudo iptables -P OUTPUT ACCEPT

  sudo iptables -F
  sudo iptables -X

  #allow openvpn
  if ip a | grep -q "tun0"; then
    if ! sudo iptables-save | grep -q "POSTROUTING -s 10.8.0.0/24"; then
      sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
    fi
    sudo iptables -A INPUT -p udp -m udp --dport 1194 -j ACCEPT
    sudo iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -s 10.8.0.0/24 -j ACCEPT
  fi
}

get_platform_match_str () {
  local val="psn-4"
  if [ "$1" == "psn" ]; then
    val="psn-4"
  elif [ "$1" == "xbox" ]; then
    val="xboxpwid:"
  elif [ "$1" == "steam" ]; then
    val="steamid:"
  fi
  echo $val
}
install_dependencies () {
  sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
  sudo ufw disable > /dev/null

  if ip a | grep -q "tun0"; then
    yn="n"
  else
    echo -e -n "${GREEN}Would you like to install OpenVPN?${NC} y/n: "
    read yn
    yn=${yn:-"y"}
  fi

  echo -e "${RED}Installing dependencies. Please wait while it finishes...${NC}"
  sudo apt-get update > /dev/null

  if [ "$yn" == "y" ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install iptables iptables-persistent ngrep nginx > /dev/null
    service nginx start
    echo -e "${RED}Installing OpenVPN. Please wait while it finishes...${NC}"
    sudo wget -q https://git.io/vpn -O openvpn-ubuntu-install.sh
    sudo chmod +x ./openvpn-ubuntu-install.sh
    (APPROVE_INSTALL=y APPROVE_IP=y IPV6_SUPPORT=n PORT_CHOICE=1 PROTOCOL_CHOICE=1 DNS=1 COMPRESSION_ENABLED=n CUSTOMIZE_ENC=n CLIENT=client PASS=1 ./openvpn-ubuntu-install.sh) &
    wait;
    sudo cp /root/client.ovpn /var/www/html/client.ovpn
    ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
    echo -e "${GREEN}You can download the openvpn config from ${BLUE}http://$ip/client.ovpn"
    ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
    echo -e "${GREEN}You can download the openvpn config from ${BLUE}http://$ip/client.ovpn"
    echo -e "${GREEN}If you are unable to access this file, you may need to allow/open the http port 80 with your vps provider."
    echo -e "Otherwise you can always run the command cat /root/client.ovpn and copy/paste ALL of its contents in a file on your PC."
    echo -e "It will be deleted automatically in 15 minutes for security reasons."
    echo -e "Be sure to import this config to your router and connect your consoles before proceeding any further.${NC}"    nohup bash -c 'sleep 900 && sudo service nginx stop && sudo apt remove nginx -y && sudo rm /var/www/html/client.ovpn' &>/dev/null &
  else
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install iptables iptables-persistent ngrep > /dev/null
  fi

}

setup () {
  echo "Setting up firewall rules."
  reset_ip_tables

  read -p "Enter your platform xbox, psn, steam: " platform
  platform=$(echo "$platform" | xargs)
  platform=${platform:-"psn"}

  reject_str=$(get_platform_match_str $platform)
  echo $platform > /tmp/data.txt

  read -p "Enter your network/netmask: " net
  net=$(echo "$net" | xargs)
  net=${net:-$DEFAULT_NET}
  echo $net >> /tmp/data.txt

  ids=()
  read -p "Would you like to sniff the ID automatically?(psn/xbox/steam) y/n: " yn
  yn=${yn:-"y"}
  if ! [[ $platform =~ ^(psn|xbox|steam)$ ]]; then
    yn="n"
  fi
  echo "n" >> /tmp/data.txt

  #auto sniffer
  if [ "$yn" == "y" ]; then

    echo -e "${RED}Press any key to stop sniffing. DO NOT CTRL C${NC}"
    sleep 1
    if [ $platform == "psn" ]; then
      #ngrep -l -q -W byline -d $INTERFACE "psn-4" udp | grep --line-buffered -o -P 'psn-4[0]{8}\K[A-F0-9]{7}' | tee -a /tmp/data.txt &
      ngrep -l -q -W byline -d $INTERFACE "psn-4" udp | grep --line-buffered -o -P | tee -a /tmp/data.txt &
    elif [ $platform == "xbox" ]; then
      ngrep -l -q -W byline -d $INTERFACE "xboxpwid:" udp | grep --line-buffered -o -P 'xboxpwid:\K[A-F0-9]{32}' | tee -a /tmp/data.txt &
    elif [ $platform == "steam" ]; then
      ngrep -l -q -W byline -d $INTERFACE "steamid:" udp | grep --line-buffered -o -P 'steamid:\K[0-9]{17}' | tee -a /tmp/data.txt &
    fi

    while [ true ] ; do
      read -t 1 -n 1
      if [ $? = 0 ] ; then
        break
      fi
    done
    pkill -15 ngrep

    #remove duplicates
    awk '!a[$0]++' /tmp/data.txt > /tmp/temp.txt && mv /tmp/temp.txt /tmp/data.txt
    #get number of accounts
    snum=$(tail -n +4 /tmp/data.txt | wc -l)
    awk "NR==4{print $snum}1" /tmp/data.txt > /tmp/temp.txt && mv /tmp/temp.txt /tmp/data.txt
    #get ids and add to ads array with identifier
    tmp_ids=$(tail -n +5 /tmp/data.txt)
    c=1
    while IFS= read -r line; do
      idf="system$c"
      ids+=( "$idf;$line" )
      ((c++))
    done <<< "$tmp_ids"
  else #add ids manually
    read -p "How many accounts are you using for this? " snum
    if [ $snum -lt 1 ]; then
      exit 1;
    fi;
    echo $snum >> /tmp/data.txt
    for ((i = 0; i < snum; i++))
    do
      num=$(( $i + 1 ))
      idf="system$num"
      read -p "Enter the sniffed ID for Account $num: " sid
      sid=$(echo "$sid" | xargs)
      echo $sid >> /tmp/data.txt
      ids+=( "$idf;$sid" )
    done
  fi;

  mv /tmp/data.txt ./data.txt


#sudo iptables -A INPUT -s 155.133.246.0/23 -j DROP
sudo iptables -A INPUT -s 185.25.182.0/24 -j DROP
sudo iptables -A INPUT -s 162.254.196.0/24 -j DROP

sudo iptables -A INPUT -s 103.10.124.0/24 -j DROP
sudo iptables -A INPUT -s 103.10.125.0/24 -j DROP
sudo iptables -A INPUT -s 103.28.54.0/24 -j DROP
sudo iptables -A INPUT -s 103.28.55.0/24 -j DROP
sudo iptables -A INPUT -s 139.45.193.0/24 -j DROP
sudo iptables -A INPUT -s 146.66.154.0/24 -j DROP
sudo iptables -A INPUT -s 146.66.155.0/24 -j DROP
sudo iptables -A INPUT -s 146.66.156.0/23 -j DROP
sudo iptables -A INPUT -s 153.254.86.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.224.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.225.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.226.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.227.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.228.0/23 -j DROP
sudo iptables -A INPUT -s 155.133.230.0/23 -j DROP
sudo iptables -A INPUT -s 155.133.232.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.233.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.234.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.235.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.238.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.239.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.242.0/23 -j DROP
sudo iptables -A INPUT -s 155.133.244.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.245.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.248.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.249.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.250.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.251.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.252.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.253.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.254.0/24 -j DROP
sudo iptables -A INPUT -s 155.133.255.0/24 -j DROP
sudo iptables -A INPUT -s 162.254.192.0/24 -j DROP
sudo iptables -A INPUT -s 162.254.193.0/24 -j DROP
sudo iptables -A INPUT -s 162.254.194.0/23 -j DROP
sudo iptables -A INPUT -s 162.254.195.0/24 -j DROP
sudo iptables -A INPUT -s 162.254.197.0/24 -j DROP
sudo iptables -A INPUT -s 162.254.198.0/24 -j DROP
sudo iptables -A INPUT -s 162.254.199.0/24 -j DROP
sudo iptables -A INPUT -s 185.25.180.0/23 -j DROP
sudo iptables -A INPUT -s 185.25.183.0/24 -j DROP
sudo iptables -A INPUT -s 190.216.121.0/24 -j DROP
sudo iptables -A INPUT -s 190.217.33.0/24 -j DROP
sudo iptables -A INPUT -s 192.69.98.0/24 -j DROP
sudo iptables -A INPUT -s 192.69.99.0/24 -j DROP
sudo iptables -A INPUT -s 205.185.194.0/24 -j DROP
sudo iptables -A INPUT -s 205.196.6.0/24 -j DROP
sudo iptables -A INPUT -s 208.64.200.0/24 -j DROP
sudo iptables -A INPUT -s 208.64.201.0/24 -j DROP
sudo iptables -A INPUT -s 208.64.202.0/24 -j DROP
sudo iptables -A INPUT -s 208.64.203.0/24 -j DROP
sudo iptables -A INPUT -s 208.78.164.0/24 -j DROP
sudo iptables -A INPUT -s 208.78.165.0/24 -j DROP
sudo iptables -A INPUT -s 208.78.166.0/24 -j DROP
sudo iptables -A INPUT -s 208.78.184.0/24 -j DROP
sudo iptables -A INPUT -s 45.121.184.0/23 -j DROP
sudo iptables -A INPUT -s 45.121.186.0/23 -j DROP



  echo "-m string --string $reject_str --algo bm -j REJECT" > reject.rule
  sudo iptables -I FORWARD -m string --string $reject_str --algo bm -j REJECT

  n=${#ids[*]}
  INDEX=1
  for (( i = n-1; i >= 0; i-- ))
  do
    elem=${ids[i]}
    offset=$((n - 2))
    if [ $INDEX -gt $offset ]; then
      inet=$net
    else
      inet="0.0.0.0/0"
    fi
    IFS=';' read -r -a id <<< "$elem"
    sudo iptables -N "${id[0]}"
    sudo iptables -I FORWARD -s $inet -p udp -m string --string "${id[1]}" --algo bm -j "${id[0]}"
    ((INDEX++))
  done

  INDEX1=1
  for i in "${ids[@]}"
  do
    IFS=';' read -r -a id <<< "$i"
    INDEX2=1
    for j in "${ids[@]}"
    do
      if [ "$i" != "$j" ]; then
        if [[ $INDEX1 -eq 1 && $INDEX2 -eq 2 ]]; then
          inet=$net
        elif [[ $INDEX1 -eq 2 && $INDEX2 -eq 1 ]]; then
          inet=$net
        elif [[ $INDEX1 -gt 2 && $INDEX2 -lt 3 ]]; then
          inet=$net
        else
          inet="0.0.0.0/0"
        fi
        IFS=';' read -r -a idx <<< "$j"
        sudo iptables -A "${id[0]}" -s $inet -p udp -m string --string "${idx[1]}" --algo bm -j ACCEPT
      fi
      ((INDEX2++))
    done
    ((INDEX1++))
  done

  iptables-save > /etc/iptables/rules.v4

  echo "Setup is complete and matchmaking firewall is now active."
}

if [ "$action" == "setup" ]; then
  if ! command -v ngrep &> /dev/null
  then
      install_dependencies
  fi
  setup
elif [ "$action" == "stop" ]; then
  echo "Matchmaking is no longer being restricted."
  reject=$(<reject.rule)
  sudo iptables -D FORWARD $reject
elif [ "$action" == "start" ]; then
  if ! sudo iptables-save | grep -q "REJECT"; then
    echo "Matchmaking is now being restricted."
    pos=$(iptables -L FORWARD | grep "system" | wc -l)
    ((pos++))
    reject=$(<reject.rule)
    sudo iptables -I FORWARD $pos $reject
  fi
elif [ "$action" == "add" ]; then
  read -p "Enter the sniffed ID: " id
  id=$(echo "$id" | xargs)
  if [ ! -z "$id" ]; then
    echo $id >> data.txt
    n=$(sed -n '4p' < data.txt)
    ((n++))
    sed -i "4c$n" data.txt
    read -p "Would you like to enter another ID? y/n " yn
    yn=${yn:-"y"}
    if [ $yn == "y" ]; then
      bash d2firewall.sh -a add
    else
      bash d2firewall.sh -a setup < data.txt
    fi
  fi
elif [ "$action" == "remove" ]; then
  list=$(tail -n +5 data.txt | cat -n)
  echo "$list"
  total=$(echo "$list" | wc -l)
  read -p "How many IDs do you want to remove from the end of this list? " num
  if [[ $num -gt 0 && $num -le $total ]]; then
    head -n -"$num" data.txt > /tmp/data.txt && mv /tmp/data.txt ./data.txt
    n=$(sed -n '4p' < data.txt)
    n=$((n-num))
    sed -i "4c$n" data.txt
    bash d2firewall.sh -a setup < data.txt
  fi;
elif [ "$action" == "sniff" ]; then
  platform=$(sed -n '1p' < data.txt)
  if ! [[ $platform =~ ^(psn|xbox|steam)$ ]]; then
      echo "Only psn,xbox, and steam are supported atm."
    exit 1
  fi
  bash d2firewall.sh -a stop

  #auto sniff
  echo -e "${RED}Press any key to stop sniffing. DO NOT CTRL C${NC}"

  sleep 1
  if [ $platform == "psn" ]; then
    ngrep -l -q -W byline -d $INTERFACE "psn-4" udp | grep --line-buffered -o -P 'psn-4[0]{20}' | tee -a data.txt &
  elif [ $platform == "xbox" ]; then
    ngrep -l -q -W byline -d $INTERFACE "xboxpwid:" udp | grep --line-buffered -o -P 'xboxpwid:\K[A-F0-9]{32}' | tee -a data.txt &
  elif [ $platform == "steam" ]; then
    ngrep -l -q -W byline -d $INTERFACE "steamid:" udp | grep --line-buffered -o -P 'steamid:\K[0-9]{17}' | tee -a data.txt &
  fi
  while [ true ] ; do
    read -t 1 -n 1
    if [ $? = 0 ] ; then
      break
    fi
  done
  pkill -15 ngrep

  #remove duplicates
  awk '!a[$0]++' data.txt > /tmp/data.txt && mv /tmp/data.txt ./data.txt

  #update total number of ids
  n=$(tail -n +5 data.txt | wc -l)
  sed -i "4c$n" data.txt

  bash d2firewall.sh -a setup < data.txt
elif [ "$action" == "list" ]; then
  tail -n +5 data.txt | cat -n
elif [ "$action" == "update" ]; then
  rm ./d2firewall.sh
  wget -q https://raw.githubusercontent.com/nKramerPT/teste/main/teste.sh -O ./d2firewall.sh
  chmod +x ./d2firewall.sh
  echo -e "${GREEN}Script update complete."
  echo -e "Please rerun the initial setup to avoid any issues.${NC}"
elif [ "$action" == "load" ]; then
  echo "Loading firewall rules."
  if [ -f ./data.txt ]; then
      bash d2firewall.sh -a setup < ./data.txt
  else
    iptables-restore < /etc/iptables/rules.v4
  fi
elif [ "$action" == "reset" ]; then
  echo "Erasing all firewall rules."
  reset_ip_tables
fi
