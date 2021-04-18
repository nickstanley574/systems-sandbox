from ldap3 import Server, Connection

conn = Connection(
    server=Server('127.0.0.1'),
    user='cn=admin,dc=brambleberry,dc=local',
    password='password123',
    auto_bind=True
)

conn.add(
    dn='cn=b.young,ou=people,dc=brambleberry,dc=local',
    attributes={
        'inetOrgPerson', {
            'givenName': 'Beatrix',
            'sn': 'Young',
            'departmentNumber': 'DEV',
            'telephoneNumber': 1111
        }
    }
)

# Rename an entry
conn.modify_dn(
    dn='cn=b.young,ou=people,dc=brambleberry,dc=local',  # old
    relative_dn='cn=b.smith'                                     # new
)
# https://ldap3.readthedocs.io/en/latest/tutorial_operations.html#update-an-entry

# Modify attributes of entry
conn.modify(
    dn='cn=b.young,ou=people,dc=brambleberry,dc=local',
    changes=''
)

conn.delete(
    dn='cn=b.young,ou=people,dc=brambleberry,dc=local'
)
