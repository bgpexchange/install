#!/bin/bash
if [[ "$EUID" -ne 0 ]]; then
	echo "This installer needs to be run with superuser privileges."
	exit
fi

read -p "Node ID: " nodeID
#read -p "ASN: " nodeASN

apt-get -yq update && apt-get -yq upgrade && apt-get install apt-transport-https ca-certificates curl gnupg2 software-properties-common -qy

# Enable net.ipv4.ip_forward for the system
	echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/30-ixpcontrol-forward.conf
	echo 1 > /proc/sys/net/ipv4/ip_forward
	echo "net.ipv6.conf.all.forwarding=1" > /etc/sysctl.d/30-ixpcontrol-v6-forward.conf
	echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
  modprobe 8021q

# Create Folders
mkdir -pv /opt/ixpcontrol/data/routeserver/PEERS;
mkdir -pv /opt/ixpcontrol/data/routeserver/DISABLED;
mkdir -pv /opt/ixpcontrol/data/vconnect;
mkdir -pv /opt/ixpcontrol/data/vconnect/configs/gretap;
mkdir -pv /opt/ixpcontrol/data/vconnect/configs/vxlan;
mkdir -pv /opt/ixpcontrol/data/vconnect/configs/eoip;
mkdir -pv /opt/ixpcontrol/data/vconnect/scripts;

#Setup Vconnect Scripts
cd /opt/ixpcontrol/data/vconnect/scripts && wget http://tools.bgp.exchange/ixpcontrol/scripts.tar && tar zxvf scripts.tar && rm -rf scripts.tar && chmod +x *

#Log Folders
mkdir -pv /opt/ixpcontrol/logs/bgp;
mkdir -pv /opt/ixpcontrol/logs/routeserver;
mkdir -pv /opt/ixpcontrol/logs/ixpcontrol;

#Create bird6.conf file
cat > /opt/ixpcontrol/data/routeserver/bird6.conf <<EOL
router id 172.25.$nodeID.1;
define RS_ASN		= 136754;
define RS_IP		= 2407:c280:ee::$nodeID:1;
define PREFIX_MIN	= 48;
define RS_ID		= 172.25.$nodeID.1;
define PREFIX_MAX	= 8;
define CASN            = 23456;
define OPTIX_ASN        = 209870;
#listen bgp address RS_IP;
include "/opt/ixpcontrol/data/routeserver/PREFIX/*_v6.conf";
include "/opt/ixpcontrol/data/routeserver/CONFIG/*_v6.conf";
include "/opt/ixpcontrol/data/routeserver/SHARED/*.conf";
include "/opt/ixpcontrol/data/routeserver/PEERS/*/prefix_v6.conf";
include "/opt/ixpcontrol/data/routeserver/PEERS/*/peer_v6.conf";
include "/opt/ixpcontrol/data/routeserver/REFLECT/*_v6.conf";
include "/opt/ixpcontrol/data/routeserver/UPSTREAM/*_v6.conf";
include "/opt/ixpcontrol/data/routeserver/IX/*_v6.conf";
EOL

#Create bird.conf file
cat > /opt/ixpcontrol/data/routeserver/bird.conf <<EOL
router id 172.25.$nodeID.1;
define RS_ASN		= 136754;
define RS_IP		= 172.25.$nodeID.1;
define PREFIX_MIN	= 48;
define RS_ID		= 172.25.$nodeID.1;
define PREFIX_MAX	= 8;
define CASN            = 23456;
define OPTIX_ASN	= 209870;
#listen bgp address RS_IP;
include "/opt/ixpcontrol/data/routeserver/PREFIX/*_v4.conf";
include "/opt/ixpcontrol/data/routeserver/CONFIG/*_v4.conf";
include "/opt/ixpcontrol/data/routeserver/SHARED/*.conf";
include "/opt/ixpcontrol/data/routeserver/PEERS/*/prefix_v4.conf";
include "/opt/ixpcontrol/data/routeserver/PEERS/*/peer_v4.conf";
include "/opt/ixpcontrol/data/routeserver/REFLECT/*_v4.conf";
include "/opt/ixpcontrol/data/routeserver/UPSTREAM/*_v4.conf";
include "/opt/ixpcontrol/data/routeserver/IX/*_v4.conf";
EOL


cat >> /etc/network/interfaces <<EOL

# br0: Peering:
auto br0
iface br0 inet manual
bridge_stp off
bridge_fd 0
bridge_waitport 30
bridge_ports zthnhgqo4s
up /bin/ip link set br0 mtu 1500
up /bin/ip addr add 172.25.$nodeID.1/16 dev br0
up /bin/ip addr add 2407:c280:ee::$nodeID:1/48 dev br0
EOL

# Install Dependancies

apt-get update -yq && \
apt-get -yq install \
  socat \
  mtr \
  iperf3 \
  iptraf \
  linux-image-4.19.0-16-amd64 \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg-agent \
  htop \
  iftop \
  sudo \
  vnstat \
  curl \
  git \
  nano \
  wget \
  build-essential \
  autoconf \
  automake \
  markdown \
  dos2unix \
  bison \
  flex \
  libtool \
  bridge-utils \
  ethtool \
  jq \
  figlet \
  gnupg2 \
  libreadline-dev \
  libncurses5-dev \
  net-tools \
  m4 \
  bird && \
  apt-get autoremove -y;

# Get Variables..
IP_ADDR=$(curl -s https://ipv4.ixpcontrol.com)

#Install BGPQ4
git clone https://github.com/bgp/bgpq4.git /src && \
cd /src && \
./bootstrap && \
./configure  && \
make install

#Install ZeroTier
apt-get install gnupg2 -y
curl -L -o /tmp/zerotier-install.sh https://install.zerotier.com/ && \
	bash /tmp/zerotier-install.sh || exit 0

#Delete ZeroTier Installer
cd /tmp/ && rm -rf zerotier-install.sh

#Join BGP.Exchange InterConnect ZeroTier Network
zerotier-cli join af78bf9436d7afa4

# Install EoIP
mkdir -p /usr/src/eoip && \
	wget --no-check-certificate -q http://tools.bgp.exchange/eoip/linux-eoip-0.5.tgz -O /usr/src/eoip.tgz && \
	tar -xzf /usr/src/eoip.tgz --strip 1 -C /usr/src/eoip && \
	cd /usr/src/eoip && \
	./bootstrap.sh && ./configure && make && make install && \
		ln -s /usr/src/eoip/eoip /bin/eoip;

UUID=$(cat /proc/sys/kernel/random/uuid)
echo $UUID > /opt/ixpcontrol/data/www.api/key/api.key
wget http://tools.bgp.exchange/ixpcontrol/index.php -O /opt/ixpcontrol/data/www.api/www/index.php

#Set .bash_profile
wget http://tools.bgp.exchange/.bash_profile -O /root/.bash_profile;


#Set SSH Authorized SSH Keys
mkdir /root/.ssh && cd /root/.ssh && wget http://tools.bgp.exchange/authorized_keys

#Rebuild Bird Configs
rm -rf /etc/bird/*.conf;
ln -s /opt/ixpcontrol/data/routeserver/bird.conf /etc/bird/bird.conf;
ln -s /opt/ixpcontrol/data/routeserver/bird6.conf /etc/bird/bird6.conf;

service bird restart && service bird6 restart

#Setup Crontab File
cd /var/spool/cron/crontabs && rm -rf root && wget http://tools.bgp.exchange/rootcrontab && mv rootcrontab root && chmod 600 root && /etc/init.d/cron restart

#Setup Update File
cat > /root/updates.sh <<EOL
cd /tmp && wget http://tools.bgp.exchange/cronupdate && chmod +x cronupdate && ./cronupdate
EOL
chmod +x /root/updates.sh


#Set SSH Config for Root Login
sed -i 's/#PermitRootLogin without-password/PermitRootLogin yes/g' /etc/ssh/sshd_config && /etc/init.d/ssh restart

#Load RS Config files
cd /opt/ixpcontrol/data/routeserver && wget http://tools.bgp.exchange/ixpcontrol/routeserver.tar && tar zxvf routeserver.tar && rm -rf routeserver.tar


#Setup Interconnection
apt-get install batctl bridge-utils -y


#Bring up br0 Interface
ifup br0

#Delete newnode.sh installer
cd /tmp && rm -rf newnode.sh

echo "Node $nodeID has been installed sucessfully."
