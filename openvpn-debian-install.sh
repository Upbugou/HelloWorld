#!/bin/bash
# OpenVPN install script for Debian/Ubuntu systems

echo "Starting OpenVPN installation script"
IPTABLES="/sbin/iptables"
IPTABLES_SAVE="/sbin/iptables-save"
IPTABLES_RESTORE="/sbin/iptables-restore"
PACKAGELIST="openvpn libssl-dev openssl expect"
OPENVPN_LOGDIR="/var/log/openvpn"
LOG_FILE="/var/log/openvpn-install.log"
TIME_STAMP=`date "+%Y-%m-%d %T"`
CWD="$(pwd)"
# get the first wlan ip
ip=$(ifconfig|grep -v 127.0.0|grep -v ":10."|grep "inet addr"|awk '{print $2}'|sed 's/addr://'|head -n1)
[ "$(whoami)" != "root" ] && exit 1
[ ! -f "$IPTABLES" ] && PACKAGELIST="$PACKAGELIST iptables"
# Update local package repos and installing required packages
apt-get -y update 2>&1
apt-get -y install $PACKAGELIST 2>&1
# Configuring.
cp -R /usr/share/doc/openvpn/examples/easy-rsa /etc/openvpn
chmod +rwx /etc/openvpn/easy-rsa/2.0
cd /etc/openvpn/easy-rsa/2.0
source ./vars >/dev/null 2>&1
./clean-all >/dev/null 2>&1
(echo -e "\n\n\n\n\n\n\n" | ./build-ca >/dev/null 2>&1)
./build-dh >/dev/null 2>&1
openvpn --genkey --secret keys/ta.key >/dev/null 2>&1
[ ! -d /etc/openvpn/keys ] && mkdir -p /etc/openvpn/keys
[ ! -d /etc/openvpn/client/keys ] && mkdir -p /etc/openvpn/client/keys
# Build server
expect <<-EOF
spawn ./build-key-server server
expect "Country*"
send "CN\n"
expect "State or*"
send "FJ\n"
expect "Locality*"
send "fz\n"
expect "Organization Name*"
send "foxit\n"
expect "Organizational Unit*"
send "it\n"
expect "Common Name*"
send "server\n"
expect "Name*"
send "foxit\n"
expect "Email Address*"
send "openvpn@foxitsoftware.com\n"
expect "*[]"
send "\n"
expect "*[]"
send "\n"
expect "*y/n*"
send "y\n"
expect "*y/n*"
send "y\n"
expect eof
exit
EOF
# Build client
expect <<-EOF
spawn ./build-key it
expect "Country*"
send "CN\n"
expect "State or*"
send "FJ\n"
expect "Locality*"
send "fz\n"
expect "Organization Name*"
send "foxit\n"
expect "Organizational Unit*"
send "it\n"
expect "Common Name*"
send "it\n"
expect "Name*"
send "foxit\n"
expect "Email Address*"
send "openvpn@foxitsoftware.com\n"
expect "*[]"
send "\n"
expect "*[]"
send "\n"
expect "*y/n*"
send "y\n"
expect "*y/n*"
send "y\n"
expect eof
exit
EOF
# server.conf
cat <<EOF > /etc/openvpn/server.conf
port 1985
proto tcp
dev tun
ca   keys/ca.crt
cert keys/server.crt
key  keys/server.key
dh   keys/dh1024.pem
server 10.66.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1"
push "dhcp-option DNS 8.8.8.8"
tls-auth keys/ta.key 0
keepalive 5 120
comp-lzo
max-clients 15
client-to-client
duplicate-cn
persist-key
persist-tun
user nobody
group nogroup
script-security 3
auth-user-pass-verify /etc/openvpn/checkpsw.sh via-env
username-as-common-name
verb 3
mssfix 1300
log         /var/log/openvpn/openvpn.log
log-append  /var/log/openvpn/openvpn.log
status      /var/log/openvpn/openvpn-status.log
EOF
# client.ovpn
cat <<EOF > /etc/openvpn/client/client.ovpn
client
dev tun
proto tcp
remote $ip 1985
resolv-retry infinite
nobind
persist-key
persist-tun
ca   keys/ca.crt
cert keys/it.crt
key  keys/it.key
auth-user-pass psd.txt
ns-cert-type server
tls-auth keys/ta.key 1
comp-lzo
verb 3
ping 10
ping-restart 60
EOF

cp /etc/openvpn/easy-rsa/2.0/keys/{ca.crt,ca.key,server.crt,server.key,dh1024.pem,ta.key} /etc/openvpn/keys
cp /etc/openvpn/easy-rsa/2.0/keys/{ca.crt,ca.key,it.crt,it.key,dh1024.pem,ta.key} /etc/openvpn/client/keys

# tar client files.
cd /etc/openvpn/client && tar cvpf /etc/openvpn/client.tar keys/{ca.crt,it.crt,it.key,dh1024.pem,ta.key} client.ovpn
wget http://openvpn.se/files/other/checkpsw.sh -O/etc/openvpn/checkpsw.sh >/dev/null 2>&1
if [ $? -ne 0 ]; then
echo $TIME_STAMP: checkpsw.sh failed to download. >> $LOG_FILE
fi
cd /etc/openvpn
if [ -f checkpsw.sh ]; then
touch psw-file
chmod +x checkpsw.sh
sed -i 's/^LOG_FILE.*/LOG_FILE="\/var\/log\/openvpn\/openvpn-password.log"/g' checkpsw.sh
fi
[ ! -d "$OPENVPN_LOGDIR" ] && mkdir -p $OPENVPN_LOGDIR
chown nobody.nogroup $OPENVPN_LOGDIR
# Network configuration.
# enable ip_forward and add iptables rules.
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
$IPTABLES -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
$IPTABLES -A FORWARD -s 10.66.0.0/24 -j ACCEPT
$IPTABLES -t nat -A POSTROUTING -j MASQUERADE
$IPTABLES_SAVE > /etc/iptables.conf
echo "#!/bin/bash
$IPTABLES_RESTORE < /etc/iptables.conf" > /etc/network/if-up.d/iptables
chmod +x /etc/network/if-up.d/iptables
/etc/init.d/openvpn restart
