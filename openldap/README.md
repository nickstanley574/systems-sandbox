# Openldap sandbox

## ❗❕❗**This is not production ready!!!!!**

The goal is to built a system where if it goes down you DON'T NEED TO RESTORE FROM A BACKUP. This might sound odd, but backups may contain custom hacks, one of mistake etc. Instead I like building systems that the first think you attempt is to rebuild from scatch so 1. you know your system is repoducable 2. you remove custom hacks.

## phpldapadmin

## openldap

## smbldap-tools

## Python ldap3

## Resources Read

* [AGDLP - Wikipedia](https://en.wikipedia.org/wiki/AGDLP)
* [Directory Services 101: Setting up an LDAP server](https://daenney.github.io/2018/10/27/ldap-server-setup)
* [Configuring Samba with LDAP authentication (on Centos/RHEL 7)](https://admin.shamot.cz/?p=470)
* [How To Install and Configure OpenLDAP and phpLDAPadmin on an Ubuntu 14.04 Server | DigitalOcean](https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-openldap-and-phpldapadmin-on-an-ubuntu-14-04-server)
* [How To Install, Configure and Test Open Ldap Server For Ubuntu – POFTUT](https://www.poftut.com/install-configure-test-open-ldap-server-ubuntu/)
* [How To Manage and Use LDAP Servers with OpenLDAP Utilities | DigitalOcean](https://www.digitalocean.com/community/tutorials/how-to-manage-and-use-ldap-servers-with-openldap-utilities)
* [How to Install and Configure OpenLDAP Server on Ubuntu 16.04 Step by Step](https://www.linuxbabe.com/ubuntu/install-configure-openldap-server-ubuntu-16-04)
* [How to Install phpLDAPadmin on CentOS 7 | HostAdvice](https://hostadvice.com/how-to/how-to-install-phpldapadmin-on-centos-7/)
* [Install OpenLDAP with phpLDAPAdmin on ubuntu | by Dinesh Kumar K B | Analytics Vidhya | Medium](https://medium.com/analytics-vidhya/install-openldap-with-phpldapadmin-on-ubuntu-9e56e57f741e)
* [Install and Configure Open LDAP - Tutorialspoint](https://www.tutorialspoint.com/linux_admin/install_and_configure_open_ldap.htm)
* [Install and Setup OpenLDAP Server on Ubuntu 20.04 - kifarunix.com](https://kifarunix.com/install-and-setup-openldap-server-on-ubuntu-20-04/)
* [Install and Setup phpLDAPadmin on Ubuntu 20.04 - kifarunix.com](https://kifarunix.com/install-and-setup-phpldapadmin-on-ubuntu-20-04/)
* [LDAP/MigrationTools - Debian Wiki](https://wiki.debian.org/LDAP/MigrationTools)
* [Ldapwiki: Directory Information Tree](https://ldapwiki.com/wiki/Directory%20Information%20Tree)
* [Open LDAP configuration](https://www.ibiblio.org/oswg/oswg-nightly/oswg/en_US.ISO_8859-1/articles/exchange-replacement-howto/exchange-replacement-howto/x213.html)
* [OpenLDAP - How To Add a User - Tyler's Guides](https://tylersguides.com/guides/openldap-how-to-add-a-user/)
* [OpenLDAP Software 2.4 Administrator's Guide](https://www.openldap.org/doc/admin24/guide.html)
* [Samba & LDAP - SambaWiki](https://wiki.samba.org/index.php/Samba_&_LDAP)
* [Samba - OpenLDAP Backend | Ubuntu](https://ubuntu.com/server/docs/samba-openldap-backend)
* [Service - LDAP | Ubuntu](https://ubuntu.com/server/docs/service-ldap)
* [Setting up OpenLDAP on CentOS 6](http://docs.adaptivecomputing.com/viewpoint/hpc/Content/topics/1-setup/installSetup/settingUpOpenLDAPOnCentos6.htm#addOU)
* [[SOLVED] Script install slapd with admin ldap password](https://www.linuxquestions.org/questions/linux-server-73/script-install-slapd-with-admin-ldap-password-4175426002/)
* [openSUSE Software](https://software.opensuse.org/package/smbldap-tools)
* [openldap - LDAP best way to assign Roles to users - Stack Overflow](https://stackoverflow.com/questions/37915255/ldap-best-way-to-assign-roles-to-users)
* [phpldapadmin_functions/functions.php at master · probsJustin/phpldapadmin_functions · GitHub](https://github.com/probsJustin/phpldapadmin_functions/blob/master/functions.php)


The explanation is very simple, when you create an object in a LDAP directory, this object MUST be with a SINGLE structural class. 