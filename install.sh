# Sets up default LEMP Stack on Ubuntu (16.04x64) 
# Nginx ( > 1.10 )
# MariaDB ( > 10.0 )
# PHP ( > 7.0 )
# PHP-FPM ( > 5.5 )

# Usage wget -qO wpvps http://bit.ly/1rNcYTM && sudo bash ./wpvps

# Configuration
SERVERNAMEORIP="localhost"
NGX_PAGESPEED_VERSION="1.11.33.2"
PWD=$(pwd)


# Echo errors in red
function wpvps_echo_fail()
{
  echo $(tput setaf 1)$@$(tput sgr0)
}

## Pre-flight checks
# Check for appropriate privileges
if [[ $EUID -ne 0 ]]; then
  wpvps_echo_fail "Sudo privs required."
  exit 100
fi

# Check linux distro
readonly wpvps_distro=$(lsb_release -i | awk '{print $3}')
if [ "$wpvps_distro" != "Ubuntu" ]; then
  wpvps_echo_fail "WPVPS only works on Ubuntu. Sorry. :("
  exit 100
fi

# Check Ubuntu version
readonly wpvps_version=$(lsb_release -sc)
if [ "$wpvps_version" != "xenial" ]; then
  wpvps_echo_fail "Please upgrade to Ubuntu 16.04 LTS and retry WPVPS."
  exit 100
fi

## Start install
# Update everything
sudo apt-get update
sudo apt-get -y upgrade
sudo apt-get -y dist-upgrade

# Install some stuff we’re going to need
sudo apt-get install -y wget unzip git openssl

# Make sure nginx is not installed because we're going to compile from source
sudo apt-get remove -y nginx nginx-common nginx-full nginx-core

# Add official repository
wget http://nginx.org/keys/nginx_signing.key
sudo apt-key add nginx_signing.key

sudo sed -i '$ a\ deb http://nginx.org/packages/mainline/ubuntu/ xenial nginx' /etc/apt/sources.list
sudo sed -i '$ a\ deb-src http://nginx.org/packages/mainline/ubuntu/ xenial nginx' /etc/apt/sources.list

sudo apt-get update

# download nginx source package
mkdir ~/nginx && cd ~/nginx
apt-get source nginx

NGINX_VERSION=$(ls|grep .gz|egrep -o '?[0-9]+\.[0-9]+\.[0-9]+')

#
cd ~
wget https://codeload.github.com/pagespeed/ngx_pagespeed/zip/v${NGX_PAGESPEED_VERSION}-beta
unzip v${NGX_PAGESPEED_VERSION}-beta
cd ngx_pagespeed-${NGX_PAGESPEED_VERSION}-beta

wget https://dl.google.com/dl/page-speed/psol/${NGX_PAGESPEED_VERSION}.tar.gz
tar xvf ${NGX_PAGESPEED_VERSION}.tar.gz

sudo sed -i '$ a\ deb http://nginx.org/packages/mainline/ubuntu/ xenial nginx' /etc/apt/sources.list
sudo sed '/$(WITH_HTTP2) \/--add-module=/home/<username>/ngx_pagespeed-1.9.32.10-beta \'~/nginx/nginx-${NGINX_VERSION}/debian/rules

cd ~/nginx/nginx-${NGINX_VERSION}/
sudo apt-get build-dep nginx
sudo dpkg-buildpackage -b

sudo dpkg -i nginx_${NGINX_VERSION}-1~trusty_amd64.deb

# Database name and password
MYSQLDATABASERAND=$(sudo openssl rand -base64 8)
MYSQLDATABASE="${SERVERNAMEORIP}_${MYSQLDATABASERAND}"
MYSQLROOTPASS=$(sudo openssl rand -base64 32)
MYSQLUSER=$(sudo openssl rand -base64 32)
MYSQLUSERPASS=$(sudo openssl rand -base64 32)

# you may need to enter a password for mysql-server
sudo debconf-set-selections <<< "mariadb-server mariadb-server/root_password password ${MYSQLROOTPASS}"
sudo debconf-set-selections <<< "mariadb-server mariadb-server/root_password_again password ${MYSQLROOTPASS}"

# install Nginx, PHP, MariaDB
sudo apt-get install -y nginx php-fpm php-gd php-mysql php7.0-mbstring mariadb-server mariadb-client

# configure php-fpm settings
sudo sed -i "s/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php/7.0/fpm/php.ini


# Setup default nginx configuration
cd /etc/nginx
sudo rm nginx.conf
sudo wget https://raw.githubusercontent.com/NathanDJohnson/box/master/nginx.conf
sudo chown www-data:www-data nginx.conf
CPUINFO=grep --count processor /proc/cpuinfo
sudo sed -i "s/^worker_processes 1;/worker_processes ${CPUINFO};/" /etc/nginx/nginx.conf

cd /etc/nginx/sites-available/
sudo rm default
sudo wget https://raw.githubusercontent.com/NathanDJohnson/box/master/default.conf
sudo chown www-data:www-data default.conf
sudo mv default.conf ${SERVERNAMEORIP}

mkdir /usr/share/nginx/cache

# restart services
sudo service nginx restart
sudo service mysql restart
sudo service php7.0-fpm restart

# create MySql Database
sudo mysql -uroot -p$MYSQLROOTPASS -e "CREATE DATABASE ${MYSQLDATABASE}"
sudo mysql -uroot -p$MYSQLROOTPASS -e "CREATE USER ${MYSQLUSER}@localhost IDENTIFIED BY ${MYSQLUSERPASS}"
sudo mysql -uroot -p$MYSQLROOTPASS -e "GRANT ALL PRIVILEGES ON ${MYSQLDATABASE}.* TO ${MYSQLUSER}"
sudo mysql -uroot -p$MYSQLROOTPASS -e "FLUSH PRIVILEGES"

# secure mariadb install
sudo mysql_secure_installation

# install WordPress
cd /usr/share/nginx/html
wget http://wordpress.org/latest.tar.gz
tar -xvzf latest.tar.gz


# move WordPress to web woot
mv /usr/share/nginx/html/wordpress/* /usr/share/nginx/html/


# make uploads and must-use plugins directories
sudo mkdir /usr/share/nginx/html/wp-content/uploads
sudo mkdir /usr/share/nginx/html/wp-content/mu-plugins

# install must-use plugins
cd /usr/share/nginx/html/wp-content/mu-plugins
sudo wget https://raw.githubusercontent.com/roots/wp-password-bcrypt/master/wp-password-bcrypt.php

# set file permissions and ownership
cd /usr/share/nginx/html
sudo find -type f -exec chmod 664 {} \;
sudo find -type d -exec chmod 775 {} \;
sudo chown www-data:www-data * -R

# delete unneeded files
sudo rm latest.tar.gz index.html 50x.html readme.html

# cleanup folder
rm -rf wordpress

# Done!
cd ${PWD}
