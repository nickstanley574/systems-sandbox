#!/bin/bash

# yum -y install httpd
# yum -y install mod_ssl

# setenforce 0 # NEED TO CHANGE

# firewall-cmd --zone=public --permanent --add-service=http
# firewall-cmd --zone=public --permanent --add-service=https
# firewall-cmd --reload

# systemctl enable httpd
# systemctl restart httpd

# hostname

set -x

# Run System Update

dnf -y -q update

# Install LDAP Self Service Password Tool on CentOS 8

dnf -y -q install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
dnf -y -q install http://rpms.remirepo.net/enterprise/remi-release-8.rpm
dnf -y -q module reset php
dnf -y -q module enable php:remi-7.3

dnf -y -q localinstall http://ltb-project.org/archives/self-service-password-1.3-1.el7.noarch.rpm

dnf -y -q install php-mcrypt vim

# Configuring LDAP Self Service Password Tool

/bin/cp  /vagrant/config_ldapreset/self-service-password.conf /etc/httpd/conf.d/self-service-password.conf
/bin/cp  /vagrant/config_ldapreset/config.inc.local.php /usr/share/self-service-password/conf/config.inc.local.php


systemctl restart httpd
systemctl enable httpd
firewall-cmd --add-port=80/tcp --permanent
firewall-cmd --reload

setsebool -P httpd_can_network_connect 1
setsebool -P httpd_can_connect_ldap 1
setsebool -P authlogin_nsswitch_use_ldap 1
setsebool -P nis_enabled 1

hostname
