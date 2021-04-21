#!/bin/python3

import os, sys
import json, yaml
import hashlib

from ldap3 import Server, Connection
from ldap3 import MODIFY_ADD, MODIFY_DELETE, MODIFY_REPLACE
from ldap3 import SUBTREE, BASE
from ldap3.core.exceptions import *

ldap_suffix     = 'dc=brambleberry,dc=local'
sambaSID        = 'S-1-5-21-3794605451-3872955435-2260215407-1016'
admin_user      = 'admin'
admin_cred      = 'password123'

# MODES
# - DEFAULT: modify/create/delete
# - EC_SYNC (eventual consistency)
# - HARDSYNC (Resync Everything)

def log(logtype, message):
    print(f"{logtype:<10} {message}")
    if logtype == "CRITICAL":
        sys.exit(2)

class LDAP:

    def __init__(self):

        self.ldap_conn = Connection(
            server    = Server('127.0.0.1'),
            user      = f'cn={admin_user},{ldap_suffix}',
            password  = admin_cred,
            auto_bind = True
        )

        self.num_hits        = 0
        self.num_search_hits = 0
        self.num_modify_hits = 0

        self.invalid_users         = []
        self.invalid_group_members = {}

        self.users_dict_uid = {}
        self.users_dict_eid = {}
        self.group_dict     = {}

        self.user_eips = []
        self.user_md5s = []

        self.__user_populate()

        self.number_of_users = len(self.user_eips)


    # Private helpers

    def __user_populate(self):
        for userEntry in self.__user_search(['*']):
            dn = userEntry.entry_dn
            try:
                user_eid    = userEntry.employeeNumber.value
                user_md5    = userEntry.carLicense.value
                user_uid    = userEntry.uid.value

                self.users_dict_uid[user_uid] = {
                    'm5':       user_md5,
                    'eid':      user_eid,
                    'curr_groups'   : [],
                    'dn'            : dn
                }
                self.users_dict_eid[user_eid] = {
                    'm5':       user_md5,
                    'uid':      user_uid,
                    'curr_groups': [],
                    'dn'         : dn
                }
                self.user_eips.append(user_eid)
                self.user_md5s.append(user_md5)
            except LDAPCursorAttributeError as e:
                log("WARNING", f"Invalid configured user - {userEntry.entry_dn}")
                self.invalid_users.append(userEntry)

        for g in self.get_all_groups():
            self.group_dict[g] = []

        for e in self.__group_search(['cn', 'memberUid']):
            memberUids  = e.memberUid.value
            group       = e.cn.value

            if      memberUids       == None:   members = []
            elif    type(memberUids) == str:    members = [memberUids]
            elif    type(memberUids) == list:   members = memberUids
            else:                               log("CRITICAL", f"Unknown MemberUid State {group} - {memberUids}")

            for user_uid in members:
                self.group_dict[group].append(user_uid)
                if user_uid not in self.users_dict_uid.keys():
                    if e.cn.value not in self.invalid_group_members.keys():
                        self.invalid_group_members[e.cn.value] = []
                    log("WARNING", f"Unknown user {user_uid} in group {e.cn.value}.")
                    self.invalid_group_members[e.cn.value].append(user_uid)
                else:
                    self.users_dict_uid[user_uid]['curr_groups'].append(e.cn.value)


    def __check_result(self, result, val='unknown', acceptable=[]):
        self.num_hits += 1

        if self.ldap_conn.result['type'] == 'modifyResponse':
            self.num_modify_hits += 1
        elif self.ldap_conn.result['type'] == 'searchResDone' :
            self.num_search_hits += 1

        if result != True and self.ldap_conn.result['result'] != 0:
            error = self.ldap_conn.result['description']
            if error in acceptable:
                log("WARNING", f"{error}: {val}")
            else:
                log("CRITICAL",  f"{val} {self.ldap_conn.result}")


    def __sambaDomainName_unique(self, attribute):
        result = self.ldap_conn.search(
            search_base     = f'sambaDomainName=sambaDomain,{ldap_suffix}',
            search_filter   = '(objectClass=*)',
            search_scope    = 'SUBTREE',
            attributes      = [attribute]
        )
        self.__check_result(result)
        number = self.ldap_conn.entries[0][attribute].values[0] + 1
        result = self.ldap_conn.modify(
            dn      = f'sambaDomainName=sambaDomain,{ldap_suffix}',
            changes = {attribute:[ (MODIFY_REPLACE, number)]})
        self.__check_result(result)
        return number


    def __group_search(self, attributes):
        result = self.ldap_conn.search(
            search_base     = f'ou=group,{ldap_suffix}',
            search_filter   = '(objectClass=posixGroup)',
            search_scope    = 'SUBTREE',
            attributes      = attributes
        )
        self.__check_result(result)
        return self.ldap_conn.entries


    def __user_search(self, attributes, uid='*'):
        result = self.ldap_conn.search(
            search_base     = f'ou=people,{ldap_suffix}',
            search_filter   = f'(&(uid={uid})(objectClass=inetOrgPerson))',
            search_scope    = 'SUBTREE',
            attributes      = attributes
        )
        self.__check_result(result)
        return self.ldap_conn.entries
    # Groups

    def group_create(self, group):
        dn = f'cn={group},ou=group,{ldap_suffix}'
        log("CREATE", f"create group {dn}")
        result = self.ldap_conn.add(
            dn = dn,
            object_class = ['top', 'posixGroup', 'SambaGroupMapping', 'extensibleObject'],
            attributes = {
                'gidNumber': self.__sambaDomainName_unique('gidNumber'),
                'sambaSID': sambaSID,
                'sambaGroupType': 2
            }
        )
        self.__check_result(result)


    def group_delete(self, group):
        dn = f'cn={group},ou=group,{ldap_suffix}'
        log('DELETE',f"delete group {dn} which included {', '.join(self.group_dict[group]) if self.group_dict[group] != [] else 'no members.'}")
        self.__check_result(self.ldap_conn.delete(dn=dn))


    def groups_enforce(self, uid, config_groups, cfg_user_md5):
        current_groups      = set(self.user_membership_preloaded(uid))
        should_be_groups    = set(config_groups)
        remove  = current_groups.difference(should_be_groups)
        add     = should_be_groups.difference(current_groups)

        if len(add) != 0:
            log("ENFORCE", f"{uid:<15} {'member of':<15} {', '.join(should_be_groups)}")
            for g in add:
                self.groups_add_user(uid, g)

        if len(remove) != 0:
            log("ENFORCE", f"{uid:<15} {'NOT member of':<15} {', '.join(remove)}")
            for g in remove:
                self.groups_remove_user(uid, g)

        if len(add) + len(remove) != 0:
            result = self.ldap_conn.modify(
                dn      = f'uid={uid},ou=people,{ldap_suffix}',
                changes = {'carLicense' :[ (MODIFY_REPLACE, cfg_user_md5)]})
            self.__check_result(result,f"[USER: {uid} MD5: {cfg_user_md5} ACTION: modify ]")


    def groups_add_user(self, uid, group):
        log("ADD", f"    * add {uid} to {group}")
        result = self.ldap_conn.modify(
            dn      = f'cn={group},ou=group,{ldap_suffix}',
            changes = {'memberUid':[(MODIFY_ADD, uid)]})
        self.__check_result(result, f"[GROUP: '{group}' USER: '{uid}', ACTION: add]",['attributeOrValueExists'])


    def groups_remove_user(self, uid, group):
        log("REMOVE", f"    * remove {uid} from {group}")
        result = self.ldap_conn.modify(
            dn      = f'cn={group},ou=group,{ldap_suffix}',
            changes = { 'memberUid':[ (MODIFY_DELETE, uid)] })
        self.__check_result(result, f"[GROUP: '{group}' USER: '{uid}', ACTION: remove]", ['noSuchAttribute'])

    # Users

    def user_create(self, uid, eip, mail, m5d, init_groups):
        dn = f'uid={uid},ou=people,{ldap_suffix}'
        log("CREATE", f"create user {dn} and to {', '.join(init_groups)}")
        result = self.ldap_conn.add(
            dn = dn,
            object_class = ['top',          'person',        'organizationalPerson',
                            'posixAccount', 'shadowAccount', 'inetOrgPerson'],
            attributes = {
                'sn'            : "TODO",
                'homeDirectory' : f"home/{uid}",
                'cn'            : f"TODO",
                'employeeNumber': eip,
                'uidNumber'     : self.__sambaDomainName_unique('uidnumber'),
                'gidNumber'     : 512,
                'mail'          : mail,
                'carLicense'    : m5d,
            }
        )
        self.__check_result(result, uid, ['entryAlreadyExists','attributeOrValueExists'])
        for group in init_groups:
            self.groups_add_user(uid, group)


    def user_rename(self, old_uid, new_uid, cfg_user_md5):
        log("RENAME", f"uid rename from {old_uid} to {new_uid}")

        result = self.ldap_conn.modify_dn(
            dn          = f'uid={old_uid},ou=people,{ldap_suffix}',
            relative_dn = f'uid={new_uid}')
        self.__check_result(result)

        for group in self.user_membership_preloaded(old_uid):
            self.groups_remove_user(old_uid, group)
            self.groups_add_user(new_uid, group)

        self.users_dict_uid[new_uid] = self.users_dict_uid[old_uid]
        del self.users_dict_uid[old_uid]

        result = self.ldap_conn.modify(
            dn      = f'uid={new_uid},ou=people,{ldap_suffix}',
            changes = {'carLicense':[ (MODIFY_REPLACE, cfg_user_md5)]})
        self.__check_result(result,f"[USER: {old_uid}->{new_uid} MD5: {cfg_user_md5} ACTION: modify ]")


    def user_delete(self, uid, dn):
        log("DELETE", f"delete user {dn}")
        for group in self.user_membership_preloaded(uid):
            self.groups_remove_user(uid, group)
        result = self.ldap_conn.delete(dn)
        self.__check_result(result, uid, ['noSuchAttribute'])


    def user_membership_preloaded(self, uid):
        if uid not in self.users_dict_uid.keys(): return []
        return self.users_dict_uid[uid]['curr_groups']


    def get_users_employeenumber(self):
        return self.user_eips


    def get_users_m5d(self):
        return self.user_md5s


    def get_all_groups(self):
        return [ e.cn.value for e in self.__group_search(['cn']) ]


def main():
    HARDENFORCE = False
    YAML_LDAP_FILE = 'ldap_config.yaml'

    log("STARTING","Loading Configs...")
    log("SETTING", f"Hard enforce is set to {HARDENFORCE}.")
    log("SETTING", f"LDAP yaml config file {YAML_LDAP_FILE}.")

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

    log("INFO", "Preloading Group and User Info...")

    ldap = LDAP()

    active_groups = ldap.get_all_groups()
    config_groups = ldap_cfg_file['groups'] + [ f"role-{role}" for role in ldap_cfg_file['roles'].keys() ]

    log("INFO","Starting Group Create Loop ...")
    for group in config_groups:
        if group not in active_groups:
            ldap.group_create(group)

    ###################
    # USER MANAGEMENT #
    ###################

    log("INFO","Starting User Create/Update/Enforce Loop ...")


    config_users = []

    for cfg_user_eip in ldap_cfg_file['users']:

        cfg_user_groups = get_user_groups(cfg_user_eip)

        userinfo = ldap_cfg_file['users'][cfg_user_eip]

        userinfo['groups'] = cfg_user_groups

        cfg_user_uid = userinfo['ldap']['uid']
        cfg_user_str = json.dumps(userinfo)
        cfg_user_md5 = hashlib.md5(cfg_user_str.encode()).hexdigest()

        config_users.append(cfg_user_uid)

        # Create New User
        if str(cfg_user_eip) not in ldap.get_users_employeenumber():
            mail  =  userinfo['ldap']['mail']
            ldap.user_create(cfg_user_uid, cfg_user_eip, mail, cfg_user_md5, cfg_user_groups)
        # Modify Current User
        elif cfg_user_md5 not in ldap.get_users_m5d():
            curr_user_uid = ldap.users_dict_eid[str(cfg_user_eip)]['uid']
            if curr_user_uid != cfg_user_uid:
                ldap.user_rename(curr_user_uid, cfg_user_uid, cfg_user_md5)
            ldap.groups_enforce(cfg_user_uid, cfg_user_groups, cfg_user_md5)
        # Enforce User Groups
        else:
            ldap.groups_enforce(cfg_user_uid, cfg_user_groups, cfg_user_md5)


    log("INFO","Starting User Delete Loop ...")
    for uid in ldap.users_dict_uid.keys():
        if uid not in config_users:
            ldap.user_delete(uid, ldap.users_dict_uid[uid]['dn'])

    log("INFO", "Starting Group Delete Loop ...")
    for group in active_groups:
        if group not in config_groups:
            ldap.group_delete(group)

    if HARDENFORCE:
        log("INFO","Hard Enforce enabled removing invalid/unknown users/groups...")
        for userEntry in ldap.invalid_users:
            ldap.user_delete(userEntry.uid.value, userEntry.entry_dn)
        for group, members in ldap.invalid_group_members.items():
            for uid in members:
                ldap.groups_remove_user(uid, group)

    log("INFO", "Changing actions completed.")

    executionTime = (time.time() - startTime)

    log("METRICS", 'Execution time in seconds:  ' + str(round(executionTime,3)))
    log("METRICS", 'Total LDAP users:           ' + str(ldap.number_of_users))
    log("METRICS", 'Number of search LDAP hits: ' + str(ldap.num_search_hits))
    log("METRICS", 'Number of change LDAP hits: ' + str(ldap.num_modify_hits))
    log("METRICS", 'Number of  total LDAP hits: ' + str(ldap.num_hits))

    if not HARDENFORCE:
        INVALIDFOUND = False
        for userEntry in ldap.invalid_users:
            log("WARNING", f"INVALID USER {userEntry.entry_dn}")
            INVALIDFOUND = True
        for group, members in ldap.invalid_group_members.items():
            log("WARNING", f"INVALID GROUP MEMBERSHIPS {group}: {', '.join(members)}")
            INVALIDFOUND = True
        if INVALIDFOUND:
            log("INFO", "The invalid entires can be removed by enabling hard enforce.")


    log("DONE", "Until next time.")


if __name__ == "__main__":
    main()