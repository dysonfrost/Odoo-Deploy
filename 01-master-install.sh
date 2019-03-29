#!/bin/bash
ODOO_DB_USER="odoo1"
ODOO_DB_PASS="odoo1"
MASTER_IP="192.168.122.61"
SLAVE_IP="192.168.122.62"
SLAVE_USER="vagrant"
SLAVE_PASS="vagrant"
NETWORK="172.29.0.0/24"
VIP_IP="192.168.122.60"
VIP_HOST="192.168.122.60/32"
VIP_NETW="192.168.122.60/24"
VIP_INT="eth1"
COROCONF="/etc/corosync/corosync.conf"
HA_PWD="hacluster"
HA_USER="hacluster"
MASTER_NODE="srv1"
MASTER_ALT="srv1-alt"
SLAVE_NODE="srv2"
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

# allow any remote secured connection
host all all 0.0.0.0/0 md5
EOP

cat <<EOP > recovery.conf.pcmk
standby_mode = on
primary_conninfo = 'host=$VIP_IP application_name=$(hostname -s)'
recovery_target_timeline = 'latest'
EOP
EOF

echo -e "\n---- Restart Master Instance & Give master IP address ----"
sudo systemctl restart postgresql@9.6-main
sudo ip addr add $VIP_NETW dev $VIP_INT

echo -e "\n---- Stop and Disable PostgreSQL Services ----"
sudo systemctl stop postgresql@9.6-main
sudo systemctl disable postgresql@9.6-main
echo disabled > /etc/postgresql/9.6/main/start.conf

echo -e "\n---- Remove Master IP Address ----"
sudo ip addr del $VIP_NETW dev $VIP_INT

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

echo -e "\n---- Authenticate Each Node ----"
sudo pcs cluster auth $MASTER_NODE $SLAVE_NODE -u $HA_USER -p $HA_PWD
#--------------------------------------------------
# Cluster Creation
#--------------------------------------------------
echo -e "\n---- Create & Start The Cluster ----"
sudo pcs cluster setup --name $CLUSTER_NAME $MASTER_NODE,$MASTER_ALT $SLAVE_NODE,$SLAVE_ALT --force
sudo pcs cluster start --all

echo -e "\n---- Verify Cluster Membership ----"
sudo crm_mon -n1D
sudo corosync-cmapctl | grep 'members.*ip'

echo -e "\n---- Setup Cluster (MASTER ONLY) ----"
sudo pcs resource defaults migration-threshold=5
sudo pcs resource defaults resource-stickiness=10

#--------------------------------------------------
# Node Fencing
#--------------------------------------------------
echo -e "\n---- Configure password-less SSH ----"
sudo ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''


echo -e "\n---- Copy RSA keys to KVM Host ----"
sudo sshpass -p $KVM_PASS ssh-copy-id $KVM_USER@$KVM_IP

echo -e "\n---- Create STONITH resource ----"
sudo pcs cluster cib cluster1.xml
sudo pcs -f cluster1.xml stonith create fence_vm_$MASTER_NODE fence_virsh \
  pcmk_host_check="static-list" pcmk_host_list="$MASTER_NODE"        \
  ipaddr="$KVM_IP" login="$KVM_USER" port="$MASTER_NODE-d9"       \
  identity_file="/root/.ssh/id_rsa"

sudo pcs -f cluster1.xml stonith create fence_vm_$SLAVE_NODE fence_virsh \
  pcmk_host_check="static-list" pcmk_host_list="$SLAVE_NODE"        \
  ipaddr="$KVM_IP" login="$KVM_USER" port="$SLAVE_NODE-d9"       \
  identity_file="/root/.ssh/id_rsa"

sudo pcs -f cluster1.xml constraint location fence_vm_$MASTER_NODE avoids $MASTER_NODE=INFINITY
sudo pcs -f cluster1.xml constraint location fence_vm_$SLAVE_NODE avoids $SLAVE_NODE=INFINITY
sudo pcs cluster cib-push cluster1.xml

#--------------------------------------------------
# Cluster Resources
#--------------------------------------------------
echo -e "\n---- Create a new offline CIB ----"
sudo pcs cluster cib cluster1.xml

echo -e "\n---- Define the roles (master/slave) of each clone ----"
# pgsqld
sudo pcs -f cluster1.xml resource create pgsqld ocf:heartbeat:pgsqlms    \
    bindir="/usr/lib/postgresql/9.6/bin"                            \
    pgdata="/etc/postgresql/9.6/main"                               \
    datadir="/var/lib/postgresql/9.6/main"                          \
    recovery_template="/etc/postgresql/9.6/main/recovery.conf.pcmk" \
    pghost="/var/run/postgresql"                                    \
    op start timeout=60s                                            \
    op stop timeout=60s                                             \
    op promote timeout=30s                                          \
    op demote timeout=120s                                          \
    op monitor interval=15s timeout=10s role="Master"               \
    op monitor interval=16s timeout=10s role="Slave"                \
    op notify timeout=60s

# pgsql-ha
sudo pcs -f cluster1.xml resource master pgsql-ha pgsqld notify=true

echo -e "\n---- Add the IP address which should be started on the primary node ----"
sudo pcs -f cluster1.xml resource create pgsql-master-ip ocf:heartbeat:IPaddr2 \
    ip=$VIP_IP cidr_netmask=24 op monitor interval=10s

echo -e "\n---- Define the collocation between pgsql-ha & pgsql-master-ip ----"
sudo pcs -f cluster1.xml constraint colocation add pgsql-master-ip with master pgsql-ha INFINITY
sudo pcs -f cluster1.xml constraint order promote pgsql-ha then start pgsql-master-ip symmetrical=false kind=Mandatory
sudo pcs -f cluster1.xml constraint order demote pgsql-ha then stop pgsql-master-ip symmetrical=false kind=Mandatory

echo -e "\n---- Push the CIB to the cluster (MASTER ONLY) ----"
sudo pcs cluster cib-push cluster1.xml

echo -e "\n---- Completed Master Configuration Successfully ----"

