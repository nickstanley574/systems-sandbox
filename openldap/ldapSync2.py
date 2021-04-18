import os, sys
import json, yaml
import hashlib
from ldap3 import Server, Connection
from ldap3 import MODIFY_ADD, MODIFY_DELETE, MODIFY_REPLACE
from ldap3 import SUBTREE, BASE

ldap_suffix     = 'dc=brambleberry,dc=local'
sambaSID        = 'S-1-5-21-3794605451-3872955435-2260215407-1016'
admin_user      = 'admin'
admin_cred      = 'password123'

from ldapActions import *

class LDAP:

    def __init__(self):
        self.ldap_conn = Connection(
            server    = Server('127.0.0.1'),
            user      = f'cn={admin_user},{ldap_suffix}',
            password  = admin_cred,
            auto_bind = True
        )


    def group_create(self, group):
        print(f"GROUP CREATE - {group}")
        result = self.ldap_conn.add(
            dn = f'cn={group},ou=group,{ldap_suffix}',
            object_class = [
                'top', 'posixGroup', 'SambaGroupMapping',
            ],
            attributes = {
                'gidNumber': self.get_next_avaliable_gidNumber(),
                'sambaSID': sambaSID,
                'sambaGroupType': 2
            }
        )
        if result != True:
            print("ERROR")
            print(LDAP.ldap_conn.result)
            sys.exit(2)


    def group_delete(self, group):
        print(f"GROUP DELETE - {group}")
        result = self.ldap_conn.delete(dn=f'cn={group},ou=group,{ldap_suffix}')
        if result != True:
            print("ERROR")
            print(self.ldap_conn.result)
            sys.exit(2)


    def user_create(self, uid, eip, mail):
        print(f"USER CREATE - {uid}")
        result = self.ldap_conn.add(
            dn = f'uid={uid},ou=people,{ldap_suffix}',
            object_class = [
                'top',          'person',        'organizationalPerson',
                'posixAccount', 'shadowAccount', 'inetOrgPerson'
            ],
            attributes = {
                'sn': 'LASTNAME',
                'homeDirectory': f"home/{uid}",
                'cn':"CN",
                'employeeNumber':eip,
                'uidNumber': self.get_next_avaliable_uidNumber(),
                'gidNumber': 512,
                'mail': mail,
            }
        )

        if result != True:
            if self.ldap_conn.result['description'] == 'entryAlreadyExists':
                print(f"Already Exists - {uid}")
            else:
                print("ERROR")
                print(self.ldap_conn.result)
                sys.exit(2)


    def user_rename(self, curr_uid, new_uid) :
        result = self.ldap_conn.modify_dn(
            dn=f'uid={curr_uid},ou=people,{ldap_suffix}',
            relative_dn=f'uid={new_uid}')
        if result != True:
            print("ERROR")
            print(self.ldap_conn.result)
            sys.exit(2)


    def user_delete(self, uid):
        print(f"USER DELETE - {uid}")
        result = self.ldap_conn.delete(dn=f'uid={uid},ou=people,{ldap_suffix}')
        if result != True:
            if self.ldap_conn.result['description'] == 'noSuchAttribute':
                print(f"Already Gone - {uid}")
            else:
                print("ERROR")
                print(self.ldap_conn.result)
                sys.exit(2)


    def enforce_groups(self, uid, config_groups):
        print(f"Enforce Groups {uid} {config_groups}")
        current_groups = set(self.user_get_members_of(uid))
        should_be_groups = set(config_groups)
        remove = current_groups.difference(should_be_groups)
        add  = should_be_groups.difference(current_groups)
        for g in add:       self.groups_add_user(uid, g)
        for g in remove:    self.groups_remove_user(uid, g)


    def groups_add_user(self, uid, group):
        print (f"ADD {uid} to {group}")
        result = self.ldap_conn.modify(
            dn = f'cn={group},ou=group,{ldap_suffix}',
            changes = {
                'memberUid':[ (MODIFY_ADD, uid)]
            }
        )
        if result != True:
            print("ERROR")
            print(self.ldap_conn.result)
            sys.exit(2)


    def groups_remove_user(self, uid, group):
        print (f"REMOVE {uid} from {group}")
        result = self.ldap_conn.modify(
            dn = f'cn={group},ou=group,{ldap_suffix}',
            changes = {
                'memberUid':[ (MODIFY_DELETE, uid)]
            }
        )
        if result != True:
            if self.ldap_conn.result['description'] == 'noSuchAttribute':
                print(f"{uid} already not in group {group}")
            else:
                print(self.ldap_conn.result)
                sys.exit(2)


    def user_get_members_of(self, uid):
        self.ldap_conn.search(
            search_base     = f'{ldap_suffix}',
            search_filter=f'(&(cn=*)(memberUid={uid}))',
            attributes = ['cn']
        )
        return [g.cn.value for g in self.ldap_conn.entries]


    def group_get_members(self, group):
            self.ldap_conn.search(
                search_base     = f'cn={group},ou=group,{ldap_suffix}',
                search_filter   = '(objectClass=posixGroup)',
                search_scope    = 'SUBTREE',
                attributes      = ['memberUid']
            )
            print(self.ldap_conn.entries)
            for entry in self.ldap_conn.entries:
                print(entry.memberUid.values)

    def get_next_avaliable_gidNumber(self):
        self.ldap_conn.search(
            search_base     = f'sambaDomainName=sambaDomain,dc=brambleberry,dc=local',
            search_filter   = '(objectClass=*)',
            search_scope    = 'SUBTREE',
            attributes      = ['gidNumber']
        )
        gid_number = self.ldap_conn.entries[0].gidNumber.values[0] + 1

        result = self.ldap_conn.modify(
            dn = f'sambaDomainName=sambaDomain,dc=brambleberry,dc=local',
            changes = {
                'gidNumber':[ (MODIFY_REPLACE, gid_number)]
            }
        )
        if result != True:
            print("ERROR")
            print(self.ldap_conn.result)
            sys.exit(2)

        return gid_number

    def get_next_avaliable_uidNumber(self):
        self.ldap_conn.search(
            search_base     = f'ou=people,{ldap_suffix}',
            search_filter   = '(objectClass=inetOrgPerson)',
            search_scope    = 'SUBTREE',
            attributes      = ['uidNumber']
        )
        if len(self.ldap_conn.entries) == 0:
            return 1000
        else:
            return sorted([g.uidNumber.value for g in self.ldap_conn.entries])[-1] + 1

ldap = LDAP()
print(ldap.get_next_avaliable_gidNumber())

sys.exit(2)
with open('ldap_config.yaml') as file:
    ldap_cfg_file = yaml.load(file, Loader=yaml.FullLoader)

user_dir = f"{os.environ['CACHED_DIR']}/.users"
groups_dir = f"{os.environ['CACHED_DIR']}/.groups"

if not os.path.exists(user_dir):
    os.makedirs(user_dir)

if not os.path.exists(groups_dir):
    os.makedirs(groups_dir)

def get_user_groups(eip):
    user_group_membership = []
    for role in ldap_cfg_file['users'][eip]['roles']:
        user_group_membership += ldap_cfg_file['roles'][role]
        user_group_membership.append(f"role-{role}")
    return sorted(user_group_membership)





####################
# GROUP MANAGEMENT #
####################

active_groups = []
groupsfiles = os.listdir(groups_dir)

roles_groups = [f"role-{role}" for role in ldap_cfg_file['roles'].keys()]
access_groups = ldap_cfg_file['groups']
for group in access_groups + roles_groups:
    active_groups.append(group)
    grouppath = f"{groups_dir}/{group}"
    if group not in groupsfiles:
        ldap.group_create(group)
        f = open(grouppath, "x"); f.close()


groupsfiles = os.listdir(groups_dir)
for f in groupsfiles:
    if f not in active_groups:
        ldap.group_delete(f)
        os.remove(f"{groups_dir}/{f}")


###################
# USER MANAGEMENT #
###################

usersfile_dict = {}
all_users_file_eips = []
all_userfiles_m5d   = []
all_users_files = os.listdir(user_dir)

for userfile in all_users_files:
    eip, m5, uid = userfile.split("-")
    all_users_file_eips.append(eip)
    all_userfiles_m5d.append(m5)
    usersfile_dict[eip] = {
        'file': userfile,
        'm5': m5,
        'uid': uid
    }

for cfg_user_eip in ldap_cfg_file['users']:

    cfg_user_groups = get_user_groups(cfg_user_eip)

    ldap_cfg_file['users'][cfg_user_eip]['groups'] = cfg_user_groups

    cfg_user_uid = ldap_cfg_file['users'][cfg_user_eip]['ldap']['uid']
    cfg_user_str = json.dumps(ldap_cfg_file['users'][cfg_user_eip])
    cfg_user_md5 = hashlib.md5(cfg_user_str.encode()).hexdigest()

    user_filepath = f"{user_dir}/{cfg_user_eip}-{cfg_user_md5}-{cfg_user_uid}"

    # Create New User
    if str(cfg_user_eip) not in all_users_file_eips:
        mail = ldap_cfg_file['users'][cfg_user_eip]['ldap']['mail']
        ldap.user_create(cfg_user_uid, cfg_user_eip, mail)
        ldap.enforce_groups(cfg_user_uid, cfg_user_groups)
        f = open(user_filepath, "x"); f.close()

    # Modify Current User
    elif cfg_user_md5 not in all_userfiles_m5d:
        current_file  = usersfile_dict[str(cfg_user_eip)]['file']
        file_user_uid = usersfile_dict[str(cfg_user_eip)]['uid']

        if file_user_uid != cfg_user_uid:
            ldap.user_rename(file_user_uid, cfg_user_uid)
        else:
            ldap.enforce_groups(cfg_user_uid, cfg_user_groups)
        os.remove(f"{user_dir}/{current_file}")
        f = open(user_filepath, "x"); f.close()

# Delete Users
for user_files in all_users_files:
    eip, m5, uid = user_files.split("-")
    if int(eip) not in ldap_cfg_file['users'].keys():
        print(f"Delete: {user_files}")
        ldap.user_delete(uid)
        os.remove(f"{user_dir}/{user_files}")





# eventually correct
# randomly pick  
# result = addUsersInGroups(ldap_conn, 'uid=TTT,ou=people,dc=brambleberry,dc=local', 'cn=jira,ou=group,dc=brambleberry,dc=local')
# print(result)
# print(ldap_conn.result)