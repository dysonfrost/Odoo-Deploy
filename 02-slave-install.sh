#!/bin/bash
ODOO_DB_USER="odoo1"
ODOO_DB_PASS="odoo1"
MASTER_IP="192.168.122.61"
SLAVE_IP="192.168.122.62"
SLAVE_USER="vagrant"
SLAVE_PASS="vagrant"
NETWORK="192.168.122.0/24"
VIP_IP="192.168.122.60"
VIP_HOST="192.168.122.60/32"
VIP_NETW="192.168.122.60/24"
VIP_INT="eth1"
COROCONF="/etc/corosync/corosync.conf"
HA_PWD="hacluster"
HA_USER="hacluster"
MASTER_NODE="srv1"
SLAVE_NODE="srv2"
MASTER_ALT="srv1-alt"
SLAVE_ALT="srv2-alt"
CLUSTER_NAME="cluster_pgsql"
KVM_USER="esgi"
KVM_PASS="esgi"
KVM_IP="192.168.122.1"
#--------------------------------------------------
# Repository Setup
#--------------------------------------------------
echo -e "\n---- Repository Setup ----"
sudo cat <<EOF >> /etc/apt/sources.list.d/pgdg.list
deb http://apt.postgresql.org/pub/repos/apt/ stretch-pgdg main
EOF

echo -e "\n---- Update local APT cache ----"
sudo apt-get install ca-certificates -y
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add
sudo apt-get update
sudo apt-get install pgdg-keyring -y

#--------------------------------------------------
# Update Server
#--------------------------------------------------
echo -e "\n---- Update Server ----"
sudo apt-get update
sudo apt-get upgrade -y

#--------------------------------------------------
# Network Setup
#--------------------------------------------------
echo -e "\n---- Network Setup ----"
sudo sed -i '/^127.0.1.1/s/^/#/g' /etc/hosts
sudo cat <<EOF >> /etc/hosts
192.168.122.10 front-nginx odoo.mydomain.local
192.168.122.65 app-odoo2
192.168.122.64 app-odoo1
192.168.122.63 backend-pgbouncer
192.168.122.60 pgsql-vip
192.168.122.61 srv1
192.168.122.62 srv2
192.168.123.61 srv1-alt
192.168.123.62 srv2-alt
EOF

#--------------------------------------------------
# PostgreSQL & Cluster Stack Installation
#--------------------------------------------------
echo -e "\n---- PostgreSQL & Cluster Stack Installation ----"
sudo apt-get install --no-install-recommends pacemaker pacemaker-cli-utils fence-agents pcs sshpass -y
sudo apt-get install postgresql-9.6 postgresql-contrib-9.6 postgresql-client-9.6 -y
sudo apt-get install resource-agents-paf -y

echo -e "\n---- Extend systemd-tmpfiles for postgresql ----"
sudo cat <<EOF > /etc/tmpfiles.d/postgresql-part.conf
# Directory for PostgreSQL temp stat files
d /var/run/postgresql/9.6-main.pg_stat_tmp 0700 postgres postgres - -
EOF

echo -e "\n---- Apply changes immediately ----"
sudo systemd-tmpfiles --create /etc/tmpfiles.d/postgresql-part.conf

#--------------------------------------------------
# PostgreSQL Setup
#--------------------------------------------------
echo -e "\n---- PostgreSQL Setup ----"
sudo -i -u postgres bash << EOF
cd /etc/postgresql/9.6/main/

cat <<EOP >> postgresql.conf
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
hot_standby = on
hot_standby_feedback = on
logging_collector = on
EOP

cat <<EOP >> pg_hba.conf
# forbid self-replication
host replication postgres $VIP_HOST reject
host replication postgres $(hostname -s) reject

# allow any standby connection
host replication postgres 0.0.0.0/0 trust
EOP

cat <<EOP > recovery.conf.pcmk
standby_mode = on
primary_conninfo = 'host=$VIP_IP application_name=$(hostname -s)'
recovery_target_timeline = 'latest'
EOP
EOF

echo -e "\n---- Cleanup instance created by the package & clone primary ----"
sudo systemctl stop postgresql@9.6-main
sudo -i -u postgres bash << EOF
rm -rf 9.6/main/
pg_basebackup -h pgsql-vip -D ~postgres/9.6/main/ -X stream -P
cp /etc/postgresql/9.6/main/recovery.conf.pcmk ~postgres/9.6/main/recovery.conf
EOF
sudo systemctl start postgresql@9.6-main

echo -e "\n---- Stop and Disable PostgreSQL Services ----"
sudo systemctl stop postgresql@9.6-main
sudo systemctl disable postgresql@9.6-main
sudo echo disabled > /etc/postgresql/9.6/main/start.conf

#--------------------------------------------------
# Cluster Pre-requisites
#--------------------------------------------------
echo -e "\n---- Disable corosync & pacemaker ----"
sudo systemctl disable corosync # important!
sudo systemctl disable pacemaker
sudo systemctl stop pacemaker.service corosync.service

if [ -f "$COROCONF" ]
then
  echo -e "\n---- Remove corosync.conf ----"
  sudo rm -f $COROCONF
fi

echo -e "\n---- Set 'hacluster' System User ----"
echo -e "$HA_PWD\n$HA_PWD" | passwd $HA_USER
sleep 3s

echo -e "\n---- Authenticate Each Node ----"
sudo pcs cluster auth $MASTER_NODE $SLAVE_NODE -u $HA_USER -p $HA_PWD

#--------------------------------------------------
# Node Fencing
#--------------------------------------------------
echo -e "\n---- Configure password-less SSH ----"
sudo ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''


echo -e "\n---- Copy RSA keys to KVM Host ----"
sudo sshpass -p $KVM_PASS ssh-copy-id $KVM_USER@$KVM_IP

sleep 10s
echo -e "\n---- Completed Slave Configuration Successfully ----"

