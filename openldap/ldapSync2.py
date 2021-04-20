#!/bin/python3

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

# MODES
# - DEFAULT: modify/create/delete
# - EC_SYNC (eventual consistency)
# - HARDSYNC (Resync Everything)

class LDAP:

    def __init__(self):

        self.ldap_conn = Connection(
            server    = Server('127.0.0.1'),
            user      = f'cn={admin_user},{ldap_suffix}',
            password  = admin_cred,
            auto_bind = True
        )

        self.num_hits = 0
        self.num_search_hits = 0
        self.num_change_hits = 0

        self.issues = []

        self.group_dict = {}

        self.invalid_users = []

        self.users_dict_uid = {}
        self.users_dict_eid = {}
        self.user_eips = []
        self.user_md5s = []
        self.__user_populate()
        self.number_of_users = len(self.user_eips)


    # Private helpers


    def __user_populate(self):
        for userEntry in self.__user_search(['*']):
            user_eid    = userEntry.employeeNumber.value
            user_md5    = userEntry.carLicense.value
            user_uid    = userEntry.uid.value

            self.users_dict_uid[user_uid] = {
                'm5':       user_md5,
                'eid':      user_eid,
                'curr_groups'   : [],
                'dn'            : userEntry.entry_dn
            }
            self.users_dict_eid[user_eid] = {
                'm5':       user_md5,
                'uid':      user_uid,
                'curr_groups': []
            }
            self.user_eips.append(user_eid)
            self.user_md5s.append(user_md5)

        for e in self.__group_search(['cn', 'memberUid']):
            if e.memberUid.value == None:
                members = []
            elif type(e.memberUid.value) == str:
                members = [e.memberUid.value]
            elif type(e.memberUid.value) == list:
                members = e.memberUid.value
            else:
                print("ERROR -----------")
                sys.exit(2)

            for user_uid in members:
                if user_uid not in self.users_dict_uid.keys():
                    print(f"Removing unknown user {user_uid} in group {e.cn.value}")
                    self.groups_remove_user(user_uid,e.cn.value)
                else:
                    self.users_dict_uid[user_uid]['curr_groups'].append(e.cn.value)

    def __check_result(self, result, val='unknown', acceptable=[]):
        self.num_hits += 1
        if result != True and self.ldap_conn.result['result'] != 0:
            error = self.ldap_conn.result['description']
            if error in acceptable:
                print(f"WARNING:  {error} - {val}")
            else:
                print(f"ERROR:   result={result} - {self.ldap_conn.result}")
                sys.exit(2)

    def __sambaDomainName_unique(self, attribute):
        self.num_search_hits += 1
        result = self.ldap_conn.search(
            search_base     = f'sambaDomainName=sambaDomain,{ldap_suffix}',
            search_filter   = '(objectClass=*)',
            search_scope    = 'SUBTREE',
            attributes      = [attribute]
        )
        self.__check_result(result)
        number = self.ldap_conn.entries[0][attribute].values[0] + 1
        self.num_change_hits += 1
        result = self.ldap_conn.modify(
            dn = f'sambaDomainName=sambaDomain,{ldap_suffix}',
            changes = {attribute:[ (MODIFY_REPLACE, number)]})
        self.__check_result(result)
        return number


    def __group_search(self, attributes):
        self.num_search_hits += 1
        result = self.ldap_conn.search(
            search_base     = f'ou=group,{ldap_suffix}',
            search_filter   = '(objectClass=posixGroup)',
            search_scope    = 'SUBTREE',
            attributes      = attributes
        )
        self.__check_result(result)
        return self.ldap_conn.entries

    def __user_search(self, attributes, uid='*'):
        self.num_search_hits += 1
        result = self.ldap_conn.search(
            search_base     = f'ou=people,{ldap_suffix}',
            search_filter   = f'(&(uid={uid})(objectClass=inetOrgPerson))',
            search_scope    = 'SUBTREE',
            attributes      = attributes
        )
        return self.ldap_conn.entries
    # Groups

    def group_create(self, group):
        print(f"GROUP CREATE:   {group}")
        self.num_change_hits += 1
        result = self.ldap_conn.add(
            dn = f'cn={group},ou=group,{ldap_suffix}',
            object_class = [
                'top', 'posixGroup', 'SambaGroupMapping', 'extensibleObject'
            ],
            attributes = {
                'gidNumber': self.__sambaDomainName_unique('gidNumber'),
                'sambaSID': sambaSID,
                'sambaGroupType': 2
            }
        )
        self.__check_result(result)


    def group_delete(self, group):
        print(f"GROUP DELETE:  {group}")
        self.num_change_hits += 1
        result = self.ldap_conn.delete(dn=f'cn={group},ou=group,{ldap_suffix}')
        self.__check_result(result)


    def groups_enforce(self, uid, config_groups, cfg_user_md5):
        current_groups      = set(self.user_get_members_of_realish(uid))
        should_be_groups    = set(config_groups)

        remove  = current_groups.difference(should_be_groups)
        add     = should_be_groups.difference(current_groups)

        if len(add) != 0:    print(f"ENFORCE:  {uid:<15} {'member of':<15} {', '.join(add)}")
        for g in add:
            self.groups_add_user(uid, g)

        if len(remove) != 0: print(f"ENFORCE:  {uid:<15} {'NOT member of':<15} {', '.join(remove)}")
        for g in remove:
            self.groups_remove_user(uid, g)

        if (len(add) + len(remove)) != 0:
            self.num_change_hits += 1
            result = self.ldap_conn.modify(
                dn      = f'uid={uid},ou=people,{ldap_suffix}',
                changes = {
                    'carLicense' :[ (MODIFY_REPLACE, cfg_user_md5)]
                }
            )
            self.__check_result(result)


    def groups_add_user(self, uid, group):
        # print (f"ADD {uid} to {group}")
        self.num_change_hits += 1
        result = self.ldap_conn.modify(
            dn      = f'cn={group},ou=group,{ldap_suffix}',
            changes = {'memberUid':[(MODIFY_ADD, uid)]})
        self.__check_result(result,f"{group} - {uid}",['attributeOrValueExists'])


    def groups_remove_user(self, uid, group):
        # print (f"REMOVE {uid} from {group}")
        self.num_change_hits += 1
        result = self.ldap_conn.modify(
            dn      = f'cn={group},ou=group,{ldap_suffix}',
            changes = { 'memberUid':[ (MODIFY_DELETE, uid)] })
        self.__check_result(result, uid, ['noSuchAttribute'])

    # Users

    def user_create(self, uid, eip, mail, m5d, init_groups):
        print(f"USER CREATE:  {uid} add user to {', '.join(init_groups)}")
        self.num_change_hits += 1
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
                'uidNumber': self.__sambaDomainName_unique('uidnumber'),
                'gidNumber': 512,
                'mail': mail,
                'carLicense': m5d,
            }
        )
        self.__check_result(result, uid, ['entryAlreadyExists','attributeOrValueExists'])
        for g in init_groups:
            self.groups_add_user(uid, g)


    def user_rename(self, curr_uid, new_uid, cfg_user_md5):
        print(f"RENAME:  {curr_uid} -> {new_uid}")

        self.num_change_hits += 1
        result = self.ldap_conn.modify_dn(
            dn          = f'uid={curr_uid},ou=people,{ldap_suffix}',
            relative_dn = f'uid={new_uid}')

        self.__check_result(result)

        for group in self.user_get_members_of(curr_uid):
            self.groups_remove_user(curr_uid, group)
            self.groups_add_user(new_uid, group)

        self.num_change_hits += 1
        result = self.ldap_conn.modify(
            dn      = f'uid={curr_uid},ou=people,{ldap_suffix}',
            changes = {'carLicense':[ (MODIFY_REPLACE, cfg_user_md5)]})

        self.__check_result(result)


    def user_delete(self, uid, dn):
        print(f"USER DELETE - {dn}")
        # for group in self.user_get_members_of_cached(uid):
        #     self.groups_remove_user(uid, group)
        self.num_change_hits += 1
        result = self.ldap_conn.delete(dn)
        self.__check_result(result, uid, ['noSuchAttribute'])


    def user_get_members_of_real(self, uid):
        self.num_search_hits += 1
        result = self.ldap_conn.search(
            search_base     = f'{ldap_suffix}',
            search_filter   = f'(&(cn=*)(memberUid={uid}))',
            attributes      = ['cn']
        )
        self.__check_result(result)
        return  [g.cn.value for g in self.ldap_conn.entries]

    def user_get_members_of_realish(self, uid):
        return self.users_dict_uid[uid]['curr_groups']


    def user_get_members_of_cached(self, uid):
        return self.users_dict_uid[uid]['groups']

    def get_users_employeenumber(self):
        return self.user_eips

    def get_users_m5d(self):
        return self.user_md5s

    def get_all_groups(self):
        return [ e.cn.value for e in self.__group_search(['cn']) ]






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

import time
startTime = time.time()


print("Preloading Group and User Info...")
ldap = LDAP()
active_groups = ldap.get_all_groups()

config_groups = ldap_cfg_file['groups'] + [ f"role-{role}" for role in ldap_cfg_file['roles'].keys() ]

print("Starting Group Create Loop ...")
for group in config_groups:
    if group not in active_groups:
        ldap.group_create(group)

print("Starting Group Delete Loop ...")
for group in active_groups:
    if group not in config_groups:
        ldap.group_delete(group)

###################
# USER MANAGEMENT #
###################

print("Starting User Create/Update/Enforce Loop ...")


new = 0
mod = 0
enf = 0

config_users = []

for cfg_user_eip in ldap_cfg_file['users']:

    cfg_user_groups = get_user_groups(cfg_user_eip)

    ldap_cfg_file['users'][cfg_user_eip]['groups'] = cfg_user_groups

    cfg_user_uid = ldap_cfg_file['users'][cfg_user_eip]['ldap']['uid']
    cfg_user_str = json.dumps(ldap_cfg_file['users'][cfg_user_eip])
    cfg_user_md5 = hashlib.md5(cfg_user_str.encode()).hexdigest()

    config_users.append(cfg_user_uid)

    # Create New User
    if str(cfg_user_eip) not in ldap.get_users_employeenumber():
        mail = ldap_cfg_file['users'][cfg_user_eip]['ldap']['mail']
        ldap.user_create(cfg_user_uid, cfg_user_eip, mail, cfg_user_md5, cfg_user_groups)

    # Modify Current User
    elif cfg_user_md5 not in ldap.get_users_m5d():
        curr_user_uid = ldap.users_dict_eid[str(cfg_user_eip)]['uid']
        if curr_user_uid != cfg_user_uid:
            ldap.user_rename(curr_user_uid, cfg_user_uid, cfg_user_md5)
        else:
            ldap.groups_enforce(cfg_user_uid, cfg_user_groups, cfg_user_md5)

    # Enforce User Groups
    else:
        ldap.groups_enforce(cfg_user_uid, cfg_user_groups, cfg_user_md5)


print("Starting User Delete Loop ...")
for uid in ldap.users_dict_uid.keys():
    if uid not in config_users:
        ldap.user_delete(uid, ldap.users_dict_uid[uid]['dn'])


executionTime = (time.time() - startTime)
print()
print("================== Run Report ==================")
print()
print('Execution time in seconds:  ' + str(round(executionTime,3)))
print()
print(f"Total LDAP users: {ldap.number_of_users}")
print()
print('Number of LDAP search hits: ' + str(ldap.num_search_hits))
print('Number of LDAP change hits: ' + str(ldap.num_change_hits))
print('                            -')
print('Total Number of LDAP hits:  ' + str(ldap.num_hits))
print()
print
print("===============================================")
print()
print("Done.")
