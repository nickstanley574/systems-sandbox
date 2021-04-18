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

# from ldapActions import *

class LDAP:

    def __init__(self):
        self.ldap_conn = Connection(
            server    = Server('127.0.0.1'),
            user      = f'cn={admin_user},{ldap_suffix}',
            password  = admin_cred,
            auto_bind = True
        )


    def __check_result(self, result, val='unknown', acceptable=[]):
        if result != True:
            error = self.ldap_conn.result['description']
            if error in acceptable:
                print(f"{error} - {val}")
            else:
                print(f"ERROR - {self.ldap_conn.result}")
                sys.exit(2)


    def group_search(self, attributes):
        self.ldap_conn.search(
            search_base     = f'ou=group,{ldap_suffix}',
            search_filter   = '(objectClass=posixGroup)',
            search_scope    = 'SUBTREE',
            attributes      = attributes
        )
        return self.ldap_conn.entries

    def user_search(self, attributes):
        self.ldap_conn.search(
            search_base     = f'ou=people,{ldap_suffix}',
            search_filter   = '(objectClass=inetOrgPerson)',
            search_scope    = 'SUBTREE',
            attributes      = attributes
        )
        return self.ldap_conn.entries

    # Groups

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
        self.__check_result(result)


    def group_delete(self, group):
        print(f"GROUP DELETE - {group}")
        result = self.ldap_conn.delete(dn=f'cn={group},ou=group,{ldap_suffix}')
        self.__check_result(result)


    def enforce_groups(self, uid, config_groups, cfg_user_md5):
        current_groups      = set(self.user_get_members_of(uid))
        should_be_groups    = set(config_groups)
        remove = current_groups.difference(should_be_groups)
        add  = should_be_groups.difference(current_groups)
        for g in add:       self.groups_add_user(uid, g)
        for g in remove:    self.groups_remove_user(uid, g)

        result = self.ldap_conn.modify(
            dn      = f'uid={uid},ou=people,{ldap_suffix}',
            changes = {'carLicense':[ (MODIFY_REPLACE, cfg_user_md5)]})
        self.__check_result(result)

    def groups_add_user(self, uid, group):
        print (f"ADD {uid} to {group}")
        result = self.ldap_conn.modify(
            dn      = f'cn={group},ou=group,{ldap_suffix}',
            changes = {'memberUid':[(MODIFY_ADD, uid)]})
        self.__check_result(result)


    def groups_remove_user(self, uid, group):
        print (f"REMOVE {uid} from {group}")
        result = self.ldap_conn.modify(
            dn      = f'cn={group},ou=group,{ldap_suffix}',
            changes = { 'memberUid':[ (MODIFY_DELETE, uid)] })
        self.__check_result(result, uid, ['noSuchAttribute'])

    # Users

    def user_create(self, uid, eip, mail, m5d):
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
                'employeeNumber': eip,
                'uidNumber': self.get_next_avaliable_uidNumber(),
                'gidNumber': 512,
                'mail': mail,
                'carLicense': m5d
            }
        )
        self.__check_result(result, uid, ['entryAlreadyExists'])


    def user_rename(self, curr_uid, new_uid, cfg_user_md5):
        print(f"Rename {curr_uid} -> {new_uid}")
        result = self.ldap_conn.modify_dn(
            dn          = f'uid={curr_uid},ou=people,{ldap_suffix}',
            relative_dn = f'uid={new_uid}')

        self.__check_result(result)

        for group in self.user_get_members_of(curr_uid):
            self.groups_remove_user(curr_uid, group)
            self.groups_add_user(new_uid, group)

        result = self.ldap_conn.modify(
            dn      = f'uid={curr_uid},ou=people,{ldap_suffix}',
            changes = {'carLicense':[ (MODIFY_REPLACE, cfg_user_md5)]})

        self.__check_result(result)


    def user_delete(self, uid):
        print(f"USER DELETE - {uid}")
        for group in self.user_get_members_of(uid):
            self.groups_remove_user(uid, group)
        result = self.ldap_conn.delete(dn=f'uid={uid},ou=people,{ldap_suffix}')
        self.__check_result(result, uid, ['noSuchAttribute'])


    def user_get_members_of(self, uid):
        self.ldap_conn.search(
            search_base     = f'{ldap_suffix}',
            search_filter   = f'(&(cn=*)(memberUid={uid}))',
            attributes      = ['cn']
        )
        return [g.cn.value for g in self.ldap_conn.entries]


    def get_users_employeenumber(self):
        entries = self.user_search(['employeenumber'])
        return [ user.employeenumber.value for user in self.ldap_conn.entries ]

    def get_users_m5d(self):
        entries = self.user_search(['carLicense'])
        return [ user.carLicense.value for user in entries ]

    def get_all_groups(self):
        entries = self.group_search(['cn'])
        return [ e.cn.value for e in entries ]


    def __sambaDomainName_unique(self, attribute):
        self.ldap_conn.search(
            search_base     = f'sambaDomainName=sambaDomain,{ldap_suffix}',
            search_filter   = '(objectClass=*)',
            search_scope    = 'SUBTREE',
            attributes      = [attribute]
        )
        number = self.ldap_conn.entries[0][attribute].values[0] + 1

        result = self.ldap_conn.modify(
            dn = f'sambaDomainName=sambaDomain,{ldap_suffix}',
            changes = {attribute:[ (MODIFY_REPLACE, number)]})

        self.__check_result(result)

        return number


    def get_next_avaliable_gidNumber(self):
        return __sambaDomainName_unique('gidNumber')

    def get_next_avaliable_uidNumber(self):
        return __sambaDomainName_unique('uidnumber')

    def all_users_main_values(self):
        entries = self.user_search(['employeeNumber', 'carLicense', 'uid'])
        return [ [user.employeeNumber.value, user.carLicense.value, user.uid.value] for user in self.ldap_conn.entries ]


ldap = LDAP()

with open('ldap_config.yaml') as file:
    ldap_cfg_file = yaml.load(file, Loader=yaml.FullLoader)

def get_user_groups(eip):
    user_group_membership = []
    for role in ldap_cfg_file['users'][eip]['roles']:
        user_group_membership += ldap_cfg_file['roles'][role]
        user_group_membership.append(f"role-{role}")
    return sorted(user_group_membership)


####################
# GROUP MANAGEMENT #
####################


active_groups = ldap.get_all_groups()
config_groups = ldap_cfg_file['groups'] + [ f"role-{role}" for role in ldap_cfg_file['roles'].keys() ]

# Create Groups
for group in config_groups:
    if group not in active_groups:
        ldap.group_create(group)

# Delete Groups
for group in active_groups:
    if group not in config_groups:
        ldap.group_delete(group)


###################
# USER MANAGEMENT #
###################

usersfile_dict = {}

for user in ldap.all_users_main_values():
    eip, m5, uid = user
    usersfile_dict[eip] = {
        'm5': m5,
        'uid': uid
    }

for cfg_user_eip in ldap_cfg_file['users']:

    cfg_user_groups = get_user_groups(cfg_user_eip)

    ldap_cfg_file['users'][cfg_user_eip]['groups'] = cfg_user_groups

    cfg_user_uid = ldap_cfg_file['users'][cfg_user_eip]['ldap']['uid']
    cfg_user_str = json.dumps(ldap_cfg_file['users'][cfg_user_eip])
    cfg_user_md5 = hashlib.md5(cfg_user_str.encode()).hexdigest()

    # Create New User
    if str(cfg_user_eip) not in ldap.get_users_employeenumber():
        mail = ldap_cfg_file['users'][cfg_user_eip]['ldap']['mail']
        ldap.user_create(cfg_user_uid, cfg_user_eip, mail, cfg_user_md5)
        ldap.enforce_groups(cfg_user_uid, cfg_user_groups, cfg_user_md5)

    # Modify Current User
    elif cfg_user_md5 not in ldap.get_users_m5d():
        file_user_uid = usersfile_dict[str(cfg_user_eip)]['uid']
        if file_user_uid != cfg_user_uid:
            ldap.user_rename(file_user_uid, cfg_user_uid, cfg_user_md5)
        else:
            ldap.enforce_groups(cfg_user_uid, cfg_user_groups, cfg_user_md5)

# Delete Users
for user_files in ldap.all_users_main_values():
    eip, m5, uid = user_files
    if int(eip) not in ldap_cfg_file['users'].keys():
        ldap.user_delete(uid)





# eventually correct
# randomly pick  
# result = addUsersInGroups(ldap_conn, 'uid=TTT,ou=people,dc=brambleberry,dc=local', 'cn=jira,ou=group,dc=brambleberry,dc=local')
# print(result)
# print(ldap_conn.result)

    # def group_get_members(self, group):
    #     entries = group_search(['employeeNumber'])

    #     self.ldap_conn.search(
    #         search_base     = f'cn={group},ou=group,{ldap_suffix}',
    #         search_filter   = '(objectClass=posixGroup)',
    #         search_scope    = 'SUBTREE',
    #         attributes      = ['employeeNumber']
    #     )
    #     print(self.ldap_conn.entries)
    #     for entry in self.ldap_conn.entries:
    #         print(entry.memberUid.values)