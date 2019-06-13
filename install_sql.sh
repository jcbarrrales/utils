#!/bin/bash

apt install iotop

wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -

sudo add-apt-repository "$(wget -qO- https://packages.microsoft.com/config/ubuntu/16.04/mssql-server-2017.list)"

sudo apt-get update

# Password for the SA user (required)
export MSSQL_SA_PASSWORD="Drakkars01"

# Use the following variables to control your install:

# Product ID of the version of SQL server you're installing
# Must be evaluation, developer, express, web, standard, enterprise, or your 25 digit product key
# Defaults to developer
export MSSQL_PID="enterprise"

# Install SQL Server Agent (recommended)
SQL_INSTALL_AGENT='y'

# Install SQL Server Full Text Search (optional)
SQL_INSTALL_FULLTEXT='y'

# TODO: Add this user!

# Create an additional user with sysadmin privileges (optional)
SQL_INSTALL_USER='BDTPRODUSER'
SQL_INSTALL_USER_PASSWORD='tY*yZF_!4$w&4UAw'

if [ -z $MSSQL_SA_PASSWORD ]
then
  echo Environment variable MSSQL_SA_PASSWORD must be set for unattended install
  exit 1
fi

echo Password for SA is $MSSQL_SA_PASSWORD...
echo PID is $MSSQL_PID...

echo Adding Microsoft repositories...
sudo curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
repoargs="$(curl https://packages.microsoft.com/config/ubuntu/16.04/mssql-server                                                                                                                                                             -2017.list)"
sudo add-apt-repository "${repoargs}"
repoargs="$(curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list)"
sudo add-apt-repository "${repoargs}"

echo Running apt-get update -y...
sudo apt-get update -y

echo Installing SQL Server...
sudo apt-get install -y mssql-server

echo Running mssql-conf setup...
sudo /opt/mssql/bin/mssql-conf -n setup accept-eula

echo Installing mssql-tools and unixODBC developer...
sudo ACCEPT_EULA=Y apt-get install -y mssql-tools unixodbc-dev

# Add SQL Server tools to the path by default:
echo Adding SQL Server tools to your path...
echo PATH="$PATH:/opt/mssql-tools/bin" >> ~/.bash_profile
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc

# Optional SQL Server Agent installation:
if [ ! -z $SQL_INSTALL_AGENT ]
then
  echo Installing SQL Server Agent...
  sudo apt-get install -y mssql-server-agent
fi

# Optional SQL Server Full Text Search installation:
if [ ! -z $SQL_INSTALL_FULLTEXT ]
then
    echo Installing SQL Server Full-Text Search...
    sudo apt-get install -y mssql-server-fts
fi

# Configure firewall to allow TCP port 1433:
echo Configuring UFW to allow traffic on port 1433...
sudo ufw allow 1433/tcp
sudo ufw reload

# Optional example of post-installation configuration.
# Trace flags 1204 and 1222 are for deadlock tracing.
# echo Setting trace flags...
# sudo /opt/mssql/bin/mssql-conf traceflag 1204 1222 on
echo Enable High Availability
sudo /opt/mssql/bin/mssql-conf set hadr.hadrenabled 1

echo Disable telemetry feedback to MS
sudo /opt/mssql/bin/mssql-conf set telemetry.customerfeedback false

echo Setup default data location

sudo mkdir -p /var/opt/mssql-data
sudo chown mssql /var/opt/mssql-data
sudo chgrp mssql /var/opt/mssql-data

sudo mkdir -p /var/opt/mssql-tlogs
sudo chown mssql /var/opt/mssql-tlogs
sudo chgrp mssql /var/opt/mssql-tlogs

sudo mkdir -p /var/opt/mssql/data/logs
sudo chown mssql /var/opt/mssql/data/logs
sudo chgrp mssql /var/opt/mssql/data/logs

sudo mkdir -p /var/opt/mssql/data/backups
sudo chown mssql /var/opt/mssql/data/backups
sudo chgrp mssql /var/opt/mssql/data/backups

sudo /opt/mssql/bin/mssql-conf set filelocation.defaultdatadir /var/opt/mssql-da                                                                                                                                                             ta
sudo /opt/mssql/bin/mssql-conf set filelocation.defaultlogdir /var/opt/mssql-tlo                                                                                                                                                             gs
sudo /opt/mssql/bin/mssql-conf set filelocation.errorlogfile /var/opt/mssql/data                                                                                                                                                             /logs/errorlog
sudo /opt/mssql/bin/mssql-conf set filelocation.defaultbackupdir /var/opt/mssql/                                                                                                                                                             data/backups
sudo /opt/mssql/bin/mssql-conf set filelocation.masterdatafile /var/opt/mssql-da                                                                                                                                                             ta/master.mdf
sudo /opt/mssql/bin/mssql-conf set filelocation.masterlogfile /var/opt/mssql-tlo                                                                                                                                                             gs/mastlog.ldf

echo Stop SQL Server...
sudo systemctl stop mssql-server

sudo /opt/mssql/bin/mssql-conf set-sa-password

echo Start SQL Server...
sudo systemctl start mssql-server

# Connect to server and get the version:
counter=1
errstatus=1
while [ $counter -le 5 ] && [ $errstatus = 1 ]
do
  echo Waiting for SQL Server to start...
  sleep 3s
  sudo /opt/mssql-tools/bin/sqlcmd \
    -S localhost \
    -U SA \
    -P $MSSQL_SA_PASSWORD \
    -Q "SELECT @@VERSION" 2>/dev/null
  errstatus=$?
  ((counter++))
done

# Display error if connection failed:
if [ $errstatus = 1 ]
then
  echo Cannot connect to SQL Server, installation aborted
  exit $errstatus
fi

# Optional new user creation:
if [ ! -z $SQL_INSTALL_USER ] && [ ! -z $SQL_INSTALL_USER_PASSWORD ]
then
  echo Creating user $SQL_INSTALL_USER
  sudo /opt/mssql-tools/bin/sqlcmd \
    -S localhost \
    -U SA \
    -P $MSSQL_SA_PASSWORD \
    -Q "CREATE LOGIN [$SQL_INSTALL_USER] WITH PASSWORD=N'$SQL_INSTALL_USER_PASSW                                                                                                                                                             ORD', DEFAULT_DATABASE=[master], CHECK_EXPIRATION=ON, CHECK_POLICY=ON; ALTER SER                                                                                                                                                             VER ROLE [sysadmin] ADD MEMBER [$SQL_INSTALL_USER]"
fi

# echo Build RAM disk for tempdb
# sudo dd if=/dev/zero of=/dev/ram1 bs=1G seek=99 count=1
# sudo mkfs.ext4 /dev/ram1
# sudo mkdir -p /var/opt/mssql/data/tempdb
# sudo mount /dev/ram1 /var/opt/mssql/data/tempdb
# sudo chown mssql /var/opt/mssql/data/tempdb
# sudo chgrp mssql /var/opt/mssql/data/tempdb

# echo Move tempdb to new location
# sudo /opt/mssql-tools/bin/sqlcmd \
#   -S localhost \
#   -U SA \
#   -P $MSSQL_SA_PASSWORD \
#   -Q "ALTER DATABASE tempdb MODIFY FILE ( NAME = tempdev, FILENAME = '/var/opt                                                                                                                                                             /mssql/data/tempdb/tempdb.mdf' )"

# sudo /opt/mssql-tools/bin/sqlcmd \
#   -S localhost \
#   -U SA \
#   -P $MSSQL_SA_PASSWORD \
#   -Q "ALTER DATABASE tempdb MODIFY FILE ( NAME = templog, FILENAME = '/var/opt                                                                                                                                                             /mssql/data/tempdb/tempdb.ldf' )"

# echo Execute AlwaysOnReadScale SQL script
# sudo /opt/mssql-tools/bin/sqlcmd \
# -S localhost \
# -U SA \
# -P $MSSQL_SA_PASSWORD \
# -i "$PWD/AlwaysOnReadScale.sql"

echo Restart MSSQL Sever
sudo systemctl restart mssql-server

# echo Install script that recreates RAM disk on restart
# sudo cp "$PWD/mount_ramdisk.sh" /opt/mssql
# sudo chmod a+x /opt/mssql/mount_ramdisk.sh
# sudo cp "$PWD/mssql-server-ramdisk.service" /etc/systemd/system
# sudo systemctl enable mssql-server-ramdisk.service

echo Done!
