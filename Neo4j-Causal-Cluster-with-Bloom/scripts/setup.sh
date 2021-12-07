############################################################################################
# Version: 0.0.1
# Created Date: 26/11/2021
# Author: Maruthi Prithivirajan
# Email: maruthi.prithivirajan@neo4j.com
# Description:
# Shell script to install Neo4j standalone with Bloom and APOC
# Coverage: Neo4j, APOC and Bloom
############################################################################################
#!/bin/bash
db_home="/home/${db_owner}"
file="$db_home/conf/neo4j.conf"

if [ ! -f $file ]; then
    #Adding Neo4j user
    sudo useradd -m ${db_owner} -s /bin/bash
    echo "${db_owner}     ALL=(ALL) NOPASSWD:ALL" | sudo EDITOR='tee -a' visudo
    sudo su -l ${db_owner}
    # Installing OpenJDK 11
    sudo apt-get update
    sudo apt-get install default-jdk unzip -y
    # Mounting storage volume for Neo4j DB datastore
    # sudo lsblk # Uncomment to check available disks
    sudo mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/sdb
    sudo mkdir /mnt/neo4j/
    # sudo chown neo4j:neo4j /data
    sudo mount -o discard,defaults /dev/sdb /mnt/neo4j/
    sudo cp /etc/fstab /etc/fstab.backup
    uuid=$(sudo blkid /dev/sdb | awk -F '"' '{print $2}')
    sudo echo "UUID=$uuid /mnt/neo4j/ discard,defaults,nofail 0 2" | sudo tee -a /etc/fstab
    # Copy DB files from GCS to VM
    sudo mkdir -p $db_home/installation-staging
    sudo gsutil -m cp -r gs://${bucket_name}/* $db_home/installation-staging
    # Unpack and setup DB files
    cd $db_home/
    sudo tar -xf installation-staging/database/neo4j-enterprise-${neo4j_version}-unix.tar.gz
    sudo mv neo4j-enterprise-${neo4j_version}/* .
    sudo mv data /mnt/neo4j/
    sudo mv import /mnt/neo4j/
    sudo chown -R ${db_owner}:${db_owner} /mnt/neo4j
    sudo unzip installation-staging/plugins/neo4j-bloom-${bloom_version}.zip
    sudo mv bloom-plugin-4* plugins
    sudo rm -f bloom-plugin-3*
    sudo rm -f neo4j-bloom-*
    sudo rm -f readme.txt
    sudo mv installation-staging/plugins/apoc-${apoc_version}-all.jar plugins
    sudo mv installation-staging/plugins/google-cloud-storage-dependencies-${gcs_version}-apoc.jar plugins
    sudo mv installation-staging/licenses/* licenses
    sudo chown -R ${db_owner}:${db_owner} $db_home/*
    # Set config properties

    # Open DB Listener
    cp conf/neo4j.conf conf/neo4j.conf.bak #backing up config just in-case :)
    sudo sed -i '/dbms\.directories\.import\=import/d' conf/neo4j.conf
    sudo tee -a conf/neo4j.conf >/dev/null <<EOT
# Default listen address
dbms.default_listen_address=0.0.0.0
# Default advertised address
dbms.default_advertised_address=${default_advertised_address}
# File imports
dbms.security.allow_csv_import_from_file_urls=true
# Directory paths
dbms.directories.data=/mnt/neo4j/data
dbms.directories.import=/mnt/neo4j/import
# Memory config
dbms.memory.heap.initial_size=${initial_heap_size}g
dbms.memory.heap.max_size=${max_heap_size}g
dbms.memory.pagecache.size=${page_cache_size}g
# DBMS Upgrade
dbms.allow_upgrade=${allow_upgrade}
# Extensions Activation
dbms.security.procedures.unrestricted=apoc.*,bloom.*
dbms.security.procedures.allowlist=apoc.*,bloom.*
dbms.unmanaged_extension_classes=com.neo4j.bloom.server=/bloom
dbms.security.http_auth_allowlist=/,/browser.*,/bloom.*
# APOC
apoc.import.file.enabled=true
apoc.export.file.enabled=true
apoc.import.file.use_neo4j_config=true
# Bloom License
neo4j.bloom.license_file=$db_home/licenses/${bloom_license}
# Causal Cluster Setup
dbms.mode=${dbms_mode}
causal_clustering.initial_discovery_members=${discovery_addresses}
causal_clustering.discovery_type=LIST
# causal_clustering.discovery_listen_address=${default_discovery_address}:5000
causal_clustering.discovery_advertised_address=${default_discovery_address}:5000
# causal_clustering.transaction_listen_address=${cluster_address}:6000
causal_clustering.transaction_advertised_address=${cluster_address}:6000
# causal_clustering.raft_listen_address=${cluster_address}:7000
causal_clustering.raft_advertised_address=${cluster_address}:7000
EOT
    # Setup as service
    sudo touch /etc/systemd/system/neo4j.service
    sudo tee -a /etc/systemd/system/neo4j.service >/dev/null <<EOT
[Unit] 
Description=Neo4j Management Service
[Service] 
Type=simple
User=${db_owner}
Group=${db_owner}
ExecStart=$db_home/bin/neo4j start
ExecStop=$db_home/bin/neo4j stop
ExecReload=$db_home/bin/neo4j restart
RemainAfterExit=no
Restart=on-failure
PIDFile=$db_home/run/neo4j.pid
LimitNOFILE=60000
TimeoutSec=6000

[Install]
WantedBy=multi-user.target
EOT
    sudo systemctl daemon-reload
    sudo systemctl enable neo4j
    sudo systemctl start neo4j
    #################################### Deprecating ####################################
    #     sudo cp bin/neo4j /etc/init.d/
    #     sudo sed -i '/BASEDIR=/d' /etc/init.d/neo4j
    #     sudo sed -i '21 i BASEDIR=`/home/neo4j`' /etc/init.d/neo4j
    #     sudo touch /etc/init.d/neo4j_ctl
    #     sudo tee -a /etc/init.d/neo4j_ctl >/dev/null <<EOT
    # #!/bin/sh
    # OWNER=neo4j #Set to the owner of the Neo4j installation
    # case "\$1" in
    # 'start')
    #     sudo service neo4j start
    #     ;;
    # 'stop')
    #     sudo service neo4j stop
    #     ;;
    # 'restart')
    #     sudo service neo4j restart
    #     ;;
    # *)
    #     echo "Usage: $0 { start | stop | restart }"
    #     exit 1
    #     ;;
    # esac
    # exit 0
    # EOT
    #     sudo chmod 755 /etc/init.d/neo4j_ctl
    #     sudo ln -s ../init.d/neo4j_ctl /etc/rc5.d/S40neo4j_ctl
    #     sudo ln -s ../init.d/neo4j_ctl /etc/rc0.d/K30neo4j_ctl
    #     sudo service neo4j start
    #################################### Deprecating ####################################
    # clean-up installation files
    sudo rm -rf installation-staging
    sudo rm -rf neo4j-enterprise-${neo4j_version}
else
    echo "Neo4j installation files exist. If you need a fresh install clean up $db_home/*"
    exit 1
fi
