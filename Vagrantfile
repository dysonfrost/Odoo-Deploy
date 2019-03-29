# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|

  # Vagrant will choose the first available provider.
  config.vm.provider "libvirt" do |_, override|
    # Set your vm IP address according to your preferred virtual priv subnet
  #  override.vm.network :private_network, :ip => "172.29.0.10"
  end
  config.vm.provider "virtualbox" do |_, override|
    # Set your vm IP address according to your preferred virtual priv subnet
    override.vm.network :private_network, :ip => "172.20.0.50"
  end


  # Master Postgres Database Virtual Machine 
  # # # WORK IN PROGRESS - MUST CREATE BOX - DO NOT DESTROY # # #
  config.vm.define "srv1" do |psql1|
    psql1.vm.hostname = "srv1"
    psql1.vm.box = "generic/debian9"
    psql1.vm.network :private_network, :ip => "192.168.122.61", :netmask => "255.255.255.0"
    psql1.vm.network :private_network, :ip => "192.168.123.61", :netmask => "255.255.255.0"

    psql1.vm.provision "file", source: "./01-master-install.sh", 
    destination: "/home/vagrant/"
    psql1.vm.provision "shell", inline: <<-EOC
      export DEBIAN_FRONTEND=noninteractive
      cd /home/vagrant
      chmod +x 01-master-install.sh
      ./01-master-install.sh
      echo "psql1.vm.provision finished"
    EOC
  end


  # Slave Postgres Database Virtual Machine
  # # # WORK IN PROGRESS - MUST CREATE BOX - DO NOT DESTROY # # #
  config.vm.define "srv2" do |psql2|
    psql2.vm.hostname = "srv2"
    psql2.vm.box = "generic/debian9"
    psql2.vm.network :private_network, :ip => "192.168.122.62", :netmask => "255.255.255.0"
    psql2.vm.network :private_network, :ip => "192.168.123.62", :netmask => "255.255.255.0"

    psql2.vm.provision "file", source: "./02-slave-install.sh", 
    destination: "/home/vagrant/"
    psql2.vm.provision "shell", inline: <<-EOC
      export DEBIAN_FRONTEND=noninteractive
      cd /home/vagrant
      chmod +x 02-slave-install.sh
      ./02-slave-install.sh
      echo "psql2.vm.provision finished"
    EOC
  end


  #  PgBouncer Relay Backend Virtual Machine
  #config.vm.define "backend-pgbouncer" do |pgb|
  #  pgb.vm.hostname = "backend-pgbouncer"
  #  pgb.vm.box = "generic/debian9"
  #  pgb.vm.network :private_network, :ip => "192.168.122.63"

    
  #  pgb.vm.provision "file", source: "./03-pgbouncer-install.sh", 
  #  destination: "/home/vagrant/"
  #  pgb.vm.provision "shell", inline: <<-EOC
  #    export DEBIAN_FRONTEND=noninteractive
  #    cd /home/vagrant
  #    chmod +x 03-pgbouncer-install.sh
  #    ./03-pgbouncer-install.sh
  #    echo "pgb.vm.provision finished"
  #  EOC
  #end


  # Main Odoo Application Virtual Machine
  config.vm.define "app-odoo1" do |od1|
    od1.vm.hostname = "app-odoo1"
    od1.vm.box = "generic/debian9"
    od1.vm.network :private_network, :ip => "192.168.122.64"

    od1.vm.provision "file", source: "./04-odoo-install.sh", 
    destination: "/home/vagrant/"
    od1.vm.provision "shell", inline: <<-EOC
      export DEBIAN_FRONTEND=noninteractive
      cd /home/vagrant
      chmod +x 04-odoo-install.sh
      ./04-odoo-install.sh
      echo "od1.vm.provision finished"
    EOC
  end


  # Second Odoo Application Virtual Machine
  config.vm.define "app-odoo2" do |od2|
    od2.vm.hostname = "app-odoo2"
    od2.vm.box = "generic/debian9"
    od2.vm.network :private_network, :ip => "192.168.122.65"

    od2.vm.provision "file", source: "./04-odoo-install.sh", 
    destination: "/home/vagrant/"
    od2.vm.provision "shell", inline: <<-EOC
      export DEBIAN_FRONTEND=noninteractive
      cd /home/vagrant
      chmod +x 04-odoo-install.sh
      ./04-odoo-install.sh
      echo "od2.vm.provision finished"
    EOC
  end


  # Main Nginx Frontend Virtual Machine
  config.vm.define "front-nginx" do |ngx|
    ngx.vm.hostname = "front-nginx"
    ngx.vm.box = "generic/debian9"
    ngx.vm.network :private_network, :ip => "192.168.122.10"

    ngx.vm.provision "file", source: "./05-nginx-install.sh", 
    destination: "/home/vagrant/"
    ngx.vm.provision "shell", inline: <<-EOC
      export DEBIAN_FRONTEND=noninteractive
      cd /home/vagrant
      chmod +x 05-nginx-install.sh
      ./05-nginx-install.sh
      echo "ngx.vm.provision finished"
    EOC
  end

#--------------------------------------------------------------------------#

  # Do not use vagrant insecure private key to access a vm.
  config.ssh.insert_key = false
  config.ssh.private_key_path = ['~/.vagrant.d/insecure_private_key', 
  '~/.ssh/vagrant_id_rsa']
  
  # Export your own public key to a provisioned vm with the SSH user vagrant.
  config.vm.provision "file", source: "~/.ssh/vagrant_id_rsa.pub", 
  destination: "~/.ssh/authorized_keys"

  # Passwordless SSH configuration.
  config.vm.provision "shell", inline: <<-EOC
    sudo sed -i -e "\\#PasswordAuthentication yes# \
    s#PasswordAuthentication yes#PasswordAuthentication no#g" \
    /etc/ssh/sshd_config
    sudo systemctl restart sshd.service
    echo "config.vm.provision finished"
  EOC
end
