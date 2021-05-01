#!/bin/bash
set -e
DC1='brambleberry'
DC2='local'
DOMAIN="$DC1.$DC2"
SUFFIX="dc=$DC1,dc=$DC2"

USER="admin"
PASSWORD="blueMoose?951?"

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



echo -n "Config slapd and openldap..."
systemctl enable slapd
systemctl start slapd

slappasswd -s $PASSWORD -n > /etc/openldap/passwd

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
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=$USER,$SUFFIX" read by * none
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

dn: ou=group,$SUFFIX
objectClass: organizationalUnit
objectClass: top
ou: group
EOF

ldapadd -x -w $PASSWORD -D cn=$USER,$SUFFIX -f /etc/openldap/base.ldif



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
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /etc/openldap/tls1.ldif

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
set +e; ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /etc/openldap/tls3.ldif  > /dev/null 2>&1; set -e
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /etc/openldap/tls2.ldif
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /etc/openldap/tls3.ldif

/bin/cp /vagrant/config/slapd /etc/sysconfig/slapd

systemctl restart slapd


echo "Config phpldapadmin and httpd..."
/bin/cp /vagrant/config/phpldapadmin.php /etc/phpldapadmin/config.php
sed -i "s/DC1/$DC1/g" /etc/phpldapadmin/config.php
sed -i "s/DC2/$DC2/g" /etc/phpldapadmin/config.php

/bin/cp /vagrant/config/phpldapadmin.conf /etc/httpd/conf.d/phpldapadmin.conf
setsebool -P httpd_can_connect_ldap on

firewall-cmd --zone=public --permanent --add-service=http
firewall-cmd --zone=public --permanent --add-service=https
firewall-cmd --zone=public --permanent --add-service=ldaps
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
echo "https://$(hostname)/phpldapadmin/" | sed 's/ //g'
echo "Admin Password: $PASSWORD"