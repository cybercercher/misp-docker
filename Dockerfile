FROM eg5846/supervisor-docker:precise
MAINTAINER Andreas Egner <andreas.egner@web.de>

## 1/ Minimal ubuntu install
# mysql is not installed -> use additional docker container (see readme)

# Upgrade system
RUN \
  apt-get update && \
  apt-get dist-upgrade -y --no-install-recommends && \
  apt-get autoremove -y && \
  apt-get clean

# Install packages
RUN echo "postfix postfix/main_mailer_type string Local only" | debconf-set-selections 
RUN echo "postfix postfix/mailname string localhost.localdomain" | debconf-set-selections
RUN \ 
  apt-get install -y --no-install-recommends apache2 curl git less libapache2-mod-php5 make mysql-client php5-gd php5-mysql php5-dev php-pear postfix redis-server sudo tree vim zip && \
  apt-get clean

## 2/ Dependencies

# Configure redis-server
RUN sed -i 's/^\(daemonize\s*\)yes\s*$/\1no/g' /etc/redis/redis.conf

# Install PEAR packages
RUN \
  pear install Crypt_GPG && \
  pear install Net_GeoIP

## 3/ MISP code

# Download MISP using git in the /var/www/ directory
RUN \
  cd /var/www && \
  git clone https://github.com/MISP/MISP.git

# Make git ignore filesystem permission differences
RUN \
  cd /var/www/MISP && \
  git config core.filemode false

## 4/ CakePHP (and CakeResque)

# CakePHP is now included as a submodule of MISP, execute the following commands to let git fetch it
RUN \
  cd /var/www/MISP && \
  git submodule init && \
  git submodule update

# Once done, install the dependencies of CakeResque if you intend to use the built in background jobs
RUN \
  cd /var/www/MISP/app/Plugin/CakeResque && \
  curl -s https://getcomposer.org/installer | php && \
  php composer.phar install

# CakeResque normally uses phpredis to connect to redis, but it has a (buggy) fallback connector through Redisent. It is highly advised to install phpredis
RUN pecl install redis
# After installing it, enable it in your php.ini file
# add the following line
RUN echo "extension=redis.so" >> /etc/php5/apache2/php.ini

# To use the scheduler worker for scheduled tasks, do the following
RUN cp -fa /var/www/MISP/INSTALL/setup/config.php /var/www/MISP/app/Plugin/CakeResque/Config/config.php

## 5/ Set the permissions

# Check if the permissions are set correctly using the following commands as root
RUN \
  chown -R www-data:www-data /var/www/MISP && \
  chmod -R 750 /var/www/MISP && \
  cd /var/www/MISP/app && \
  chmod -R g+ws tmp && \
  chmod -R g+ws files

## 6/ Create a database and user
# Included in run.sh (see readme)

## 7/ Apache configuration

# Now configure your apache server with the DocumentRoot /var/www/MISP/app/webroot/
# A sample ghost can be found in /var/www/MISP/INSTALL/apache.misp
RUN cp /var/www/MISP/INSTALL/apache.misp /etc/apache2/sites-available/misp

# Be aware that the configuration files for apache 2.4 and up have changed
# The configuration file has to have the .conf extension in the sites-available directory
# For more information, visit http://httpd.apache.org/docs/2.4/upgrading.html
RUN \
  a2dissite default && \
  a2ensite misp

# Enable modules
RUN a2enmod rewrite

## 8/ MISP configuration
# Parts are included in run.sh (see readme)
ADD gpg/.gnupg /var/www/MISP/.gnupg
RUN \
  chown -R www-data:www-data /var/www/MISP/.gnupg && \
  chmod 700 /var/www/MISP/.gnupg && \
  chmod 0600 /var/www/MISP/.gnupg/*
ADD gpg/gpg.asc /var/www/MISP/app/webroot/gpg.asc
RUN \
  chown -R www-data:www-data /var/www/MISP/app/webroot/gpg.asc && \
  chmod 0644 /var/www/MISP/app/webroot/gpg.asc

# Add modified bootstrap.default.php
ADD bootstrap.default.php /var/www/MISP/app/Config/bootstrap.default.php
RUN \
  chown www-data:www-data /var/www/MISP/app/Config/bootstrap.default.php && \
  chmod 0750 /var/www/MISP/app/Config/bootstrap.default.php

## Finished MISP INSTALL.txt

# Configure supervisord
RUN \
  echo '' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo '[program:postfix]' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'process_name = master' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'directory = /etc/postfix' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'command = /usr/sbin/postfix -c /etc/postfix start' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'startsecs = 0' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'autorestart = false' >> /etc/supervisor/conf.d/supervisord.conf

RUN \
  echo '' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo '[program:redis-server]' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'command=redis-server /etc/redis/redis.conf' >> /etc/supervisor/conf.d/supervisord.conf

RUN \
  echo '' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo '[program:apache2]' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'command=/bin/bash -c "source /etc/apache2/envvars && exec /usr/sbin/apache2 -D FOREGROUND"' >> /etc/supervisor/conf.d/supervisord.conf

RUN \
  echo '' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo '[program:resque]' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'command=/bin/bash /var/www/MISP/app/Console/worker/start.sh' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'startsecs = 0' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'autorestart = false' >> /etc/supervisor/conf.d/supervisord.conf

# Add run script
ADD run.sh /run.sh
RUN chmod 0755 /run.sh

# TODO: Expose volume with apache logs?

EXPOSE 80
CMD ["/run.sh"]
