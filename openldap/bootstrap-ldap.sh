#!/bin/bash
set -e

DC1='brambleberry'
DC2='local'
DOMAIN="$DC1.$DC2"
SUFFIX="dc=$DC1,dc=$DC2"

USER="admin"
PASSWORD="theblueMoose24680"
READONLY_PASSWORD="thegreenHawk13579"


echo -n "Installing packages..."

yum -y -q update
yum -y -q install \
    httpd \
    mod_ssl \
    openldap \
    compat-openldap \
    openldap-servers \
    openldap-devel \
    openldap-clients \
    samba \
    smbldap-tools \
    phpldapadmin \
    migrationtools \
    python3 \
    python3-devel

pip3 -q install pyyaml ldap3

yum install -y -q yum-utils
yum install -y -q http://rpms.remirepo.net/enterprise/remi-release-7.rpm
yum-config-manager --enable remi-php74
yum install -y -q php php-common php-opcache php-mcrypt php-cli php-gd php-curl php-mysql php-xml

slappasswd -s $PASSWORD -n > /etc/openldap/passwd
slappasswd -s $READONLY_PASSWORD -n > /etc/openldap/passwd_readonly


echo -n "Config slapd and openldap..."

systemctl enable slapd
systemctl start slapd


cat > /etc/openldap/changes.ldif << EOF
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: $SUFFIX

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=$USER,$SUFFIX

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $(</etc/openldap/passwd)

dn: cn=config
changetype: modify
replace: olcLogLevel
olcLogLevel: -1

dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to *
  by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read
  by dn.base="cn=$USER,$SUFFIX" read
  by * none
EOF

ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /etc/openldap/changes.ldif

ldapadd -Q -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
ldapadd -Q -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
ldapadd -Q -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif

cat > /etc/openldap/base.ldif << EOF
dn: $SUFFIX
dc: $DC1
objectClass: top
objectClass: domain

dn: ou=people,$SUFFIX
objectClass: organizationalUnit
objectClass: top
ou: people

dn: ou=system,$SUFFIX
objectClass: organizationalUnit
objectClass: top
ou: system

dn: ou=group,$SUFFIX
objectClass: organizationalUnit
objectClass: top
ou: group
EOF

ldapadd -x -w $PASSWORD -D cn=$USER,$SUFFIX -f /etc/openldap/base.ldif


cat > /etc/openldap/readonly.ldif << EOF
dn: cn=readonly,ou=system,$SUFFIX
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: readonly
userPassword: $(</etc/openldap/passwd_readonly)
description: Bind DN user for LDAP Operations
EOF
ldapadd -x -w $PASSWORD -D cn=$USER,$SUFFIX -f /etc/openldap/readonly.ldif


echo "Setup Samba LDAP backend..."

ldapadd -Q -Y EXTERNAL -H ldapi:/// -f /usr/share/doc/samba-4.10.16/LDAP/samba.ldif

/bin/cp /vagrant/config/smbldap.conf /etc/smbldap-tools/smbldap.conf
/bin/cp /vagrant/config/smbldap_bind.conf /etc/smbldap-tools/smbldap_bind.conf

sed -i "s/USER/$USER/g"          /etc/smbldap-tools/smbldap_bind.conf
sed -i "s/PASSWORD/$PASSWORD/g"  /etc/smbldap-tools/smbldap_bind.conf
sed -i "s/SUFFIX/$SUFFIX/g"      /etc/smbldap-tools/smbldap_bind.conf
sed -i "s/SUFFIX/$SUFFIX/g"      /etc/smbldap-tools/smbldap.conf

SAMBASID=$(net getlocalsid | awk '{print $NF}')

cat > /etc/openldap/samba.ldif << EOF
dn: sambaDomainName=SAMBA,$SUFFIX
objectClass: sambaDomain
sambaDomainName: SAMBA
sambaSID: $SAMBASID
sambaNextRid: 1000

dn: sambaDomainName=sambaDomain,$SUFFIX
objectClass: sambaDomain
objectClass: sambaUnixIdPool
sambaDomainName: sambaDomain
sambaSID: $SAMBASID
uidNumber: 1000
gidNumber: 1000
EOF

ldapadd -x -w $PASSWORD -D cn=$USER,$SUFFIX -f /etc/openldap/samba.ldif

cat > /etc/openldap/acl.ldif << EOF
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to attrs=userPassword
  by self write
  by anonymous auth
  by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by dn.base="cn=$USER,$SUFFIX" read
  by * none
olcAccess: {1}to attrs=shadowLastChange,shadowExpire
  by self write
  by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by dn.base="cn=$USER,$SUFFIX" read
  by * none
olcAccess: {2}to *
  by dn.exact="cn=readonly,ou=system,$SUFFIX" read
EOF
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /etc/openldap/acl.ldif


echo "Config TLS..."

/bin/cp /00-config/certs/files/_.vagrant.local.crt /etc/pki/tls/certs/
/bin/cp /00-config/certs/files/_.vagrant.local.key /etc/pki/tls/certs/
chmod 644 /etc/pki/tls/certs/_.vagrant.local.key

/bin/cp /00-config/certs/files/CA/rootCA.crt /etc/pki/ca-trust/source/anchors/rootCA.crt
update-ca-trust

cat > /etc/openldap/tls1.ldif << EOF
dn: cn=config
changetype: modify
delete: olcTLSCACertificatePath

dn: cn=config
changetype: modify
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/pki/ca-trust/source/anchors/rootCA.crt
EOF

cat > /etc/openldap/tls2.ldif << EOF
dn: cn=config
changetype: modify
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/pki/tls/certs/_.vagrant.local.key
EOF

cat > /etc/openldap/tls3.ldif << EOF
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/pki/tls/certs/_.vagrant.local.crt
EOF

# HACK!
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /etc/openldap/tls1.ldif
set +e; ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /etc/openldap/tls3.ldif  > /dev/null 2>&1; set -e
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /etc/openldap/tls2.ldif
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /etc/openldap/tls3.ldif

/bin/cp /vagrant/config/slapd /etc/sysconfig/slapd

systemctl restart slapd

# SSP

yum -y -q localinstall http://ltb-project.org/archives/self-service-password-1.3-1.el7.noarch.rpm

setsebool -P httpd_can_network_connect 1
setsebool -P httpd_can_connect_ldap 1
setsebool -P authlogin_nsswitch_use_ldap 1
setsebool -P nis_enabled 1

# /bin/cp  /vagrant/config_ldapreset/self-service-password.conf /etc/httpd/conf.d/self-service-password.conf
/bin/cp  /vagrant/config_ldapreset/config.inc.local.php /usr/share/self-service-password/conf/config.inc.local.php


echo "Config phpldapadmin and httpd..."

/bin/cp /vagrant/config/phpldapadmin.php /etc/phpldapadmin/config.php
sed -i "s/DC1/$DC1/g" /etc/phpldapadmin/config.php
sed -i "s/DC2/$DC2/g" /etc/phpldapadmin/config.php

/bin/cp /vagrant/config/phpldapadmin.conf /etc/httpd/conf.d/phpldapadmin.conf
setsebool -P httpd_can_connect_ldap on

firewall-cmd --zone=public --permanent --add-service=http
firewall-cmd --zone=public --permanent --add-service=https
firewall-cmd --zone=public --permanent --add-service=ldaps

firewall-cmd --permanent --add-port=389/tcp
firewall-cmd --permanent --add-port=636/tcp
firewall-cmd --permanent --add-port=9830/tcp

firewall-cmd --reload

systemctl enable httpd
systemctl restart httpd


echo "Config and run ldapsync ..."

DIR="/etc/ldapsync"

mkdir -p $DIR

cat > $DIR/ldapsync.config << EOF
[MAIN]
user        = $USER
password    = $PASSWORD
suffix      = $SUFFIX
sambaSID    = $SAMBASID
ldapserver  = $(hostname)
ldapyaml    = /vagrant/ldap_config.yaml
hardenforce = True
EOF

chmod 600 $DIR/ldapsync.config

/vagrant/ldapSync3.py


echo "---"
echo ""
echo "https://$(hostname)/phpldapadmin/" | sed 's/ //g'
echo "https://$(hostname)/passwordreset/" | sed 's/ //g'
echo ""
echo "dn:  cn=$USER,$SUFFIX"
echo "pwd: $PASSWORD"
echo ""
echo "dn:  cn=readonly,ou=system,$SUFFIX"
echo "pwd: $READONLY_PASSWORD"
echo ""