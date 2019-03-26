#!/bin/bash
#####################################################################################################
#----------------------------------------------------------------------------------------------------
# This script will install Postgres on your Ubuntu 16.04 server.
#-----------------------------------------------------------------------------------------------------
# Make a new file:
# sudo vim 01-postgres-install.sh
# Place this content in it and then make the file executable:
# sudo chmod +x 01-postgres-install.sh
# Execute the script to install Postgres:
# sudo ./01-postgres-install.sh
#######################################################################################################

##fixed parameters
DB_USER="odoo"
DB_PASS="odoo"

#--------------------------------------------------
# Update Server
#--------------------------------------------------
echo -e "\n---- Update Server ----"
sudo apt update
sudo apt upgrade -yV

#--------------------------------------------------
# Install PostgreSQL Server
#--------------------------------------------------
echo -e "\n---- Install PostgreSQL Server ----"
sudo apt install postgresql postgresql-server-dev-all -yV

echo -e "\n---- Creating the Odoo PostgreSQL User  ----"
sudo su - postgres -c "createuser -s $DB_USER" 2> /dev/null || true
sudo su - postgres -c "psql -c \"ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';\""
