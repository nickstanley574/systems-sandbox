#!/bin/bash
set -e
echo "SEEDING LDAP...."
echo "DC1=$DC1;DC2=$DC2"

cat << EOF > /tmp/update-mdb-acl.ldif
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: to attrs=userPassword,shadowLastChange,shadowExpire
  by self write
  by anonymous auth
  by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by dn.exact="cn=readonly,ou=people,dc=$DC1,dc=$DC2" read
  by * none
olcAccess: to dn.exact="cn=readonly,ou=people,dc=$DC1,dc=$DC2" by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage by * none
olcAccess: to dn.subtree="dc=$DC1,dc=$DC2" by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by users read
  by * none
EOF
ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/update-mdb-acl.ldif

echo "-> Structure <-"
cat << EOF > /tmp/users-ou.ldif

dn: ou=$DC1,dc=$DC1,dc=$DC2
changetype: add
objectClass: organizationalUnit
ou: $DC1

dn: ou=people,dc=$DC1,dc=$DC2
objectClass: organizationalUnit
objectClass: top
ou: people

dn: ou=groups,dc=$DC1,dc=$DC2
objectClass: organizationalUnit
objectClass: top
ou: groups

dn: ou=accounts,ou=$DC1,dc=$DC1,dc=$DC2
changetype: add
objectClass: organizationalUnit
ou: accounts

dn: ou=people,ou=accounts,ou=$DC1,dc=$DC1,dc=$DC2
changetype: add
objectClass: organizationalUnit
ou: people

dn: ou=robots,ou=accounts,ou=$DC1,dc=$DC1,dc=$DC2
changetype: add
objectClass: organizationalUnit
ou: robots

dn: ou=groups,ou=$DC1,dc=$DC1,dc=$DC2
changetype: add
objectClass: organizationalUnit
ou: groups

dn: ou=userPrivate,ou=groups,ou=$DC1,dc=$DC1,dc=$DC2
changetype: add
objectClass: organizationalUnit
ou: userPrivate
EOF
ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/users-ou.ldif

echo "-> Users <-"
cat << EOF > /tmp/users.ldif
dn: uid=johndoe,ou=people,dc=$DC1,dc=$DC2
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: johndoe
cn: John
sn: Doe
loginShell: /bin/bash
uidNumber: 10000
gidNumber: 10000
homeDirectory: /home/johndoe
shadowMax: 60
shadowMin: 1
shadowWarning: 7
shadowInactive: 7
shadowLastChange: 0

dn: cn=johndoe,ou=groups,dc=$DC1,dc=$DC2
objectClass: posixGroup
cn: johndoe
gidNumber: 10000
memberUid: johndoe

dn: uid=test,ou=people,ou=accounts,ou=$DC1,dc=$DC1,dc=$DC2
changetype: add
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: test
cn: test
sn: Tester
uidNumber: 10000
gidNumber: 10000
homeDirectory: /home/test
displayName: Testing test
mail: test@example.com
loginShell: /bin/bash
shadowExpire: 0
userPassword: {CRYPT}$6$rounds=50000$b7166V2Na/kA9Hs$Q05k3jHtVI41pNohCkFQbfWsDXEajYNDOmDj7lFX67Fvz14HmDOVaxaX8PAbysFUzkZsAv9ybQd4BSDc0JZPi.

dn: cn=test,ou=userPrivate,ou=groups,ou=$DC1,dc=$DC1,dc=$DC2
changetype: add
#objectClass: organizationalRole
objectClass: posixGroup
cn: test
gidNumber: 10000
EOF
ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/users.ldif

echo "-> readonly Users <-"
cat << EOF > readonly-user.ldif
dn: cn=readonly,ou=people,dc=$DC1,dc=$DC2
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: readonly
userPassword: {SSHA}qUwFrgsseX1ztrJ64wq63SNqGuSnLics
description: Bind DN user for LDAP Operations
EOF

ldapadd -Y EXTERNAL -H ldapi:/// -f readonly-user.ldif

echo "SEEDING LDAP COMPLETE ..."
