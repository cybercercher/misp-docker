#!/bin/bash

set -e

# Generate ssh host key
if [[ ! -e /etc/ssh/ssh_host_rsa_key ]]; then
  echo "No SSH host key available. Generating one..."
  export LC_ALL=C
  dpkg-reconfigure openssh-server
fi

# Set MYSQL_ROOT_PASSWORD
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
  echo "MYSQL_ROOT_PASSWORD is not set, use default value 'root'"
  MYSQL_ROOT_PASSWORD=root
else
  echo "MYSQL_ROOT_PASSWORD is set to '$MYSQL_ROOT_PASSWORD'" 
fi

## 6/Create a database and user  

echo "Connecting to database ..."
ret=`echo 'SHOW DATABASES;' | mysql -u root --password="$MYSQL_ROOT_PASSWORD" -h $MYSQL_PORT_3306_TCP_ADDR -P $MYSQL_PORT_3306_TCP_PORT 2>&1`

if [ $? -eq 0 ]; then
  echo "Connected to database successfully"
  found=0
  for db in $ret; do
    if [ "$db" == "misp" ]; then
      found=1
    fi    
  done
  if [ $found -eq 1 ]; then
    echo "Database misp found"
  else
    echo "Database misp not found, creating now one ..."
	cat > /tmp/create_misp_database.sql <<-EOSQL
		create database misp;
		grant usage on *.* to misp identified by 'misp';
		grant all privileges on misp.* to misp;
	EOSQL
    ret=`mysql -u root --password="$MYSQL_ROOT_PASSWORD" -h $MYSQL_PORT_3306_TCP_ADDR -P $MYSQL_PORT_3306_TCP_PORT 2>&1 < /tmp/create_misp_database.sql`
    if [ $? -eq 0 ]; then
      echo "Created database misp successfully"

      echo "Importing /var/www/MISP/INSTALL/MYSQL.sql"
      ret=`mysql -u misp --password="misp" misp -h $MYSQL_PORT_3306_TCP_ADDR -P $MYSQL_PORT_3306_TCP_PORT 2>&1 < /var/www/MISP/INSTALL/MYSQL.sql`
      if [ $? -eq 0 ]; then
        echo "Imported /var/www/MISP/INSTALL/MYSQL.sql successfully"
      else
        echo "ERROR: Importing /var/www/MISP/INSTALL/MYSQL.sql failed:"
        echo $ret
      fi
    else
      echo "ERROR: Creating database misp failed:"
      echo $ret
    fi    
  fi
else
  echo "ERROR: Connecting to database failed:"
  echo $ret
fi

# 8/ MISP configuration

cd /var/www/MISP/app/Config

cp -a bootstrap.default.php bootstrap.php

cp -a database.default.php database.php
sed -i "s/127\.0\.0\.1/$MYSQL_PORT_3306_TCP_ADDR/" database.php
sed -i "s/db\s*login/misp/" database.php
sed -i "s/8889/$MYSQL_PORT_3306_TCP_PORT/" database.php
sed -i "s/db\s*password/misp/" database.php

cp -a core.default.php core.php

chown -R www-data:www-data /var/www/MISP/app/Config
chmod -R 750 /var/www/MISP/app/Config

## TODO: Fix background jobs, does not work yet (Error: Plugin CakeResque could not be found)
##       If CakeResque is not enabled, fallback with non-background worker is used (see issue 257, redis still needed?) 
# Start workers to enable backgroud jobs
#chmod +x /var/www/MISP/app/Console/worker/start.sh
#bash /var/www/MISP/app/Console/worker/start.sh &

# Start supervisord 
cd /
exec /usr/bin/supervisord
