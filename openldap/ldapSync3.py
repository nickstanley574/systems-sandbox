#!/bin/python3

import sys
import hashlib
import time

import json
import yaml

from ldap3 import Server, Connection
from ldap3 import MODIFY_ADD, MODIFY_DELETE, MODIFY_REPLACE
from ldap3.core.exceptions import LDAPCursorAttributeError

import configparser

config = configparser.ConfigParser()
config.read('/etc/ldapsync/ldapsync.config')

ADMIN_USER   = config['MAIN']['user']
ADMIN_CRED   = config['MAIN']['password']
LDAP_SUFFIX  = config['MAIN']['suffix']
SAMBA_SID    = config['MAIN']['sambaSID']
LDAP_YAML    = config['MAIN']['ldapyaml']
LDAP_SERVER  = config['MAIN']['ldapserver']
HARD_ENFORCE = config.getboolean('MAIN','hardenforce')


def log(logtype, message):
    print(f"{logtype:<10} {message}")
    if logtype == "CRITICAL":
        sys.exit(2)

class LDAP:

    def __init__(self):

        self.ldap_conn = Connection(
            server    = Server(LDAP_SERVER),
            user      = f'cn={ADMIN_USER},{LDAP_SUFFIX}',
            password  = ADMIN_CRED,
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

            except LDAPCursorAttributeError as group_entry:
                log("WARNING", f"Invalid configured user - {userEntry.entry_dn}")
                self.invalid_users.append(userEntry)

        for group in self.get_all_groups():
            self.group_dict[group] = []

        for group_entry in self.__group_search(['cn', 'memberUid']):
            member_uids  = group_entry.memberUid.value
            group        = group_entry.cn.value

            if member_uids is None:
                members = []
            elif isinstance(member_uids, str):
                members = [member_uids]
            elif isinstance(member_uids, list):
                members = member_uids
            else:
                log("CRITICAL", f"Unknown MemberUid State {group} - {member_uids}")

            for user_uid in members:
                self.group_dict[group].append(user_uid)
                if user_uid not in self.users_dict_uid.keys():
                    if group not in self.invalid_group_members.keys():
                        self.invalid_group_members[group] = []
                    log("WARNING", f"Unknown user {user_uid} in group {group}.")
                    self.invalid_group_members[group].append(user_uid)
                else:
                    self.users_dict_uid[user_uid]['curr_groups'].append(group)


    def __check_result(self, result, val='unknown', acceptable=None):
        self.num_hits += 1
        if self.ldap_conn.result['type'] in ['modifyResponse','modDNResponse']:
            self.num_modify_hits += 1
        elif self.ldap_conn.result['type'] == 'searchResDone' :
            self.num_search_hits += 1

        if acceptable == None: acceptable = []

        if result is not True and self.ldap_conn.result['result'] != 0:
            error = self.ldap_conn.result['description']
            if error in acceptable:
                log("WARNING", f"{error}: {val}")
            else:
                log("CRITICAL",  f"{val} {self.ldap_conn.result}")


    def __sambadomainname_unique(self, attribute):
        result = self.ldap_conn.search(
            search_base     = f'sambaDomainName=sambaDomain,{LDAP_SUFFIX}',
            search_filter   = '(objectClass=*)',
            search_scope    = 'SUBTREE',
            attributes      = [attribute]
        )
        self.__check_result(result)
        number = self.ldap_conn.entries[0][attribute].values[0] + 1
        result = self.ldap_conn.modify(
            dn      = f'sambaDomainName=sambaDomain,{LDAP_SUFFIX}',
            changes = {attribute:[ (MODIFY_REPLACE, number)]})
        self.__check_result(result)
        return number


    def __group_search(self, attributes):
        result = self.ldap_conn.search(
            search_base     = f'ou=group,{LDAP_SUFFIX}',
            search_filter   = '(objectClass=posixGroup)',
            search_scope    = 'SUBTREE',
            attributes      = attributes
        )
        self.__check_result(result)
        return self.ldap_conn.entries


    def __user_search(self, attributes, uid='*'):
        result = self.ldap_conn.search(
            search_base     = f'ou=people,{LDAP_SUFFIX}',
            search_filter   = f'(&(uid={uid})(objectClass=inetOrgPerson))',
            search_scope    = 'SUBTREE',
            attributes      = attributes
        )
        self.__check_result(result)
        return self.ldap_conn.entries


    def group_create(self, group):
        dn = f'cn={group},ou=group,{LDAP_SUFFIX}'
        log("CREATE", f"create group {dn}")
        result = self.ldap_conn.add(
            dn = dn,
            object_class = ['top', 'posixGroup', 'SambaGroupMapping', 'extensibleObject'],
            attributes = {
                'gidNumber': self.__sambadomainname_unique('gidNumber'),
                'sambaSID': SAMBA_SID,
                'sambaGroupType': 2
        })
        self.__check_result(result)


    def group_delete(self, group):
        dn = f'cn={group},ou=group,{LDAP_SUFFIX}'
        members = ', '.join(self.group_dict[group]) if self.group_dict[group] != [] else 'no members.'
        log('DELETE',f"delete group {dn} which included {members}")
        self.__check_result(self.ldap_conn.delete(dn=dn))


    def groups_enforce(self, uid, config_groups, cfg_user_md5):
        current_groups      = set(self.user_membership_preloaded(uid))
        config_groups    = set(config_groups)
        remove  = current_groups.difference(config_groups)
        add     = config_groups.difference(current_groups)

        if len(add) != 0:
            log("ENFORCE", f"{uid:<15} {'member of':<15} {', '.join(config_groups)}")
            for group in add:
                self.groups_add_user(uid, group)

        if len(remove) != 0:
            log("ENFORCE", f"{uid:<15} {'NOT member of':<15} {', '.join(remove)}")
            for group in remove:
                self.groups_remove_user(uid, group)

        if len(add) + len(remove) != 0:
            result = self.ldap_conn.modify(
                dn      = f'uid={uid},ou=people,{LDAP_SUFFIX}',
                changes = {'carLicense' :[ (MODIFY_REPLACE, cfg_user_md5)]})
            self.__check_result(result,f"[USER: {uid} MD5: {cfg_user_md5} ACTION: modify ]")


    def groups_add_user(self, uid, group):
        log("ADD", f"    *    add {uid:>15}   to {group}")
        result = self.ldap_conn.modify(
            dn      = f'cn={group},ou=group,{LDAP_SUFFIX}',
            changes = {'memberUid':[(MODIFY_ADD, uid)]})
        self.__check_result(result, f"[GROUP: '{group}' USER: '{uid}', ACTION: add]",['attributeOrValueExists'])


    def groups_remove_user(self, uid, group):
        log("REMOVE", f"    * remove {uid:>15} from {group}")
        result = self.ldap_conn.modify(
            dn      = f'cn={group},ou=group,{LDAP_SUFFIX}',
            changes = { 'memberUid':[ (MODIFY_DELETE, uid)] })
        self.__check_result(result, f"[GROUP: '{group}' USER: '{uid}', ACTION: remove]", ['noSuchAttribute'])

    # Users

    def user_create(self, uid, eid, fname, lname, mail, m5d, init_groups):
        dn = f'uid={uid},ou=people,{LDAP_SUFFIX}'
        log("CREATE", f"create user {dn} and to {', '.join(init_groups)}")
        result = self.ldap_conn.add(
            dn = dn,
            object_class = ['top',          'person',        'organizationalPerson',
                            'posixAccount', 'shadowAccount', 'inetOrgPerson'],
            attributes = {
                'sn'            : lname,
                'homeDirectory' : f"home/{uid}",
                'cn'            : f"{fname} {lname}",
                'employeeNumber': eid,
                'uidNumber'     : self.__sambadomainname_unique('uidnumber'),
                'gidNumber'     : 512,
                'mail'          : mail,
                'carLicense'    : m5d,
            }
        )
        self.__check_result(result, uid, ['entryAlreadyExists','attributeOrValueExists'])
        for group in init_groups:
            self.groups_add_user(uid, group)


    def user_modify(self, uid, eid, fname, lname, mail, m5d):
        dn = f'uid={uid},ou=people,{LDAP_SUFFIX}'
        log("MODIFY", f"modify user {dn}")
        result = self.ldap_conn.modify(
            dn=dn,
            changes = {
                'carLicense': [ (MODIFY_REPLACE, m5d) ],
                'sn'        : [ (MODIFY_REPLACE, lname) ],
                'cn'        : [ (MODIFY_REPLACE, f"{fname} {lname}") ],
                'mail'      : [ (MODIFY_REPLACE, mail) ]
            }
        )
        self.__check_result(result)


    def user_rename(self, old_uid, new_uid, cfg_user_md5):
        log("RENAME", f"uid rename from {old_uid} to {new_uid}")

        result = self.ldap_conn.modify_dn(
            dn          = f'uid={old_uid},ou=people,{LDAP_SUFFIX}',
            relative_dn = f'uid={new_uid}')
        self.__check_result(result)

        for group in self.user_membership_preloaded(old_uid):
            self.groups_remove_user(old_uid, group)
            self.groups_add_user(new_uid, group)

        self.users_dict_uid[new_uid] = self.users_dict_uid[old_uid]
        del self.users_dict_uid[old_uid]

        result = self.ldap_conn.modify(
            dn      = f'uid={new_uid},ou=people,{LDAP_SUFFIX}',
            changes = {'carLicense':[ (MODIFY_REPLACE, cfg_user_md5) ]})
        self.__check_result(result,f"[USER: {old_uid} to {new_uid} MD5: {cfg_user_md5} ACTION: modify ]")


    def user_delete(self, uid, dn):
        log("DELETE", f"delete user {dn}")
        for group in self.user_membership_preloaded(uid):
            self.groups_remove_user(uid, group)
        result = self.ldap_conn.delete(dn)
        self.__check_result(result, uid, ['noSuchAttribute'])


    def user_membership_preloaded(self, uid):
        if uid not in self.users_dict_uid.keys():
            return []
        return self.users_dict_uid[uid]['curr_groups']


    def get_users_employeenumber(self):
        return self.user_eips


    def get_users_m5d(self):
        return self.user_md5s


    def get_all_groups(self):
        return [ entry.cn.value for entry in self.__group_search(['cn']) ]




###################
### MAIN SCRIPT ###
###################


def main():

    start_time = time.time()

    log("STARTING","Loading Configs...")
    log("SETTING", f"HARD_ENFORCE = {HARD_ENFORCE}")
    log("SETTING", f"USER         = {ADMIN_USER}")
    log("SETTING", f"LDAP_SERVER  = {LDAP_SERVER}")
    log("SETTING", f"LDAP_YAML    = {LDAP_YAML}")
    log("SETTING", f"LDAP_SUFFIX  = {LDAP_SUFFIX}")

    with open(LDAP_YAML) as file:
        ldap_cfg_file = yaml.load(file, Loader=yaml.FullLoader)

    log("INFO", "Preloading Group and User Info...")

    ldap = LDAP()

    active_groups = ldap.get_all_groups()
    config_groups = ldap_cfg_file['groups'] + [ f"role-{role}" for role in ldap_cfg_file['roles'].keys() ]

    log("INFO","Starting Group Create Loop ...")
    for group in config_groups:
        if group not in active_groups:
            ldap.group_create(group)

    log("INFO","Starting User Create/Update/Enforce Loop ...")

    config_users = []

    for cfg_user_eid in ldap_cfg_file['users']:

        cfg_user_groups = []
        for role in ldap_cfg_file['users'][cfg_user_eid]['roles']:
            cfg_user_groups += ldap_cfg_file['roles'][role]
            cfg_user_groups.append(f"role-{role}")

        if 'additional-access' in ldap_cfg_file['users'][cfg_user_eid]:
            for group in ldap_cfg_file['users'][cfg_user_eid]['additional-access']:
                cfg_user_groups.append(group)


        cfg_user_groups = sorted(cfg_user_groups)

        userinfo = ldap_cfg_file['users'][cfg_user_eid]
        userinfo['groups'] = cfg_user_groups

        cfg_user_eid   = str(cfg_user_eid)
        cfg_user_md5   = hashlib.md5(json.dumps(userinfo).encode()).hexdigest()

        cfg_user_fname = userinfo['fname']
        cfg_user_lname = userinfo['lname']
        cfg_user_uid   = userinfo['uid']
        try:
            cfg_user_mail  = userinfo['mail']
        except KeyError as e:
            cfg_user_mail = cfg_user_uid + "@test.com"




        config_users.append(cfg_user_uid)

        # Create New User
        if str(cfg_user_eid) not in ldap.get_users_employeenumber():
            ldap.user_create(
                cfg_user_uid,
                cfg_user_eid,
                cfg_user_fname,
                cfg_user_lname,
                cfg_user_mail,
                cfg_user_md5,
                cfg_user_groups
            )
        # Modify Current User
        elif cfg_user_md5 not in ldap.get_users_m5d():
            curr_user_uid = ldap.users_dict_eid[cfg_user_eid]['uid']

            if curr_user_uid != cfg_user_uid:
                ldap.user_rename(curr_user_uid, cfg_user_uid, cfg_user_md5)

            ldap.user_modify(
                cfg_user_uid,
                cfg_user_eid,
                cfg_user_fname,
                cfg_user_lname,
                cfg_user_mail,
                cfg_user_md5,
            )
            ldap.groups_enforce(cfg_user_uid, cfg_user_groups, cfg_user_md5)
        # Enforce User Groups
        else:
            ldap.groups_enforce(cfg_user_uid, cfg_user_groups, cfg_user_md5)


    log("INFO","Starting User Delete Loop ...")
    for uid in ldap.users_dict_uid:
        if uid not in config_users:
            ldap.user_delete(uid, ldap.users_dict_uid[uid]['dn'])

    log("INFO", "Starting Group Delete Loop ...")
    for group in active_groups:
        if group not in config_groups:
            ldap.group_delete(group)

    if HARD_ENFORCE:
        log("INFO","Hard Enforce enabled removing invalid/unknown users/groups...")
        for user_entry in ldap.invalid_users:
            ldap.user_delete(user_entry.uid.value, user_entry.entry_dn)
        for group, members in ldap.invalid_group_members.items():
            for uid in members:
                ldap.groups_remove_user(uid, group)

    log("INFO", "Changing actions completed.")

    execution_time = (time.time() - start_time)

    log("METRICS", 'Execution time in seconds:  ' + str(round(execution_time,3)))
    log("METRICS", 'Total LDAP users:           ' + str(ldap.number_of_users))
    log("METRICS", 'Number of search LDAP hits: ' + str(ldap.num_search_hits))
    log("METRICS", 'Number of change LDAP hits: ' + str(ldap.num_modify_hits))
    log("METRICS", 'Number of  total LDAP hits: ' + str(ldap.num_hits))

    if not HARD_ENFORCE:
        invalid_found = False
        for user_entry in ldap.invalid_users:
            log("WARNING", f"INVALID USER {user_entry.entry_dn}")
            invalid_found = True
        for group, members in ldap.invalid_group_members.items():
            log("WARNING", f"INVALID GROUP MEMBERSHIPS {group}: {', '.join(members)}")
            invalid_found = True
        if invalid_found:
            log("INFO", "The invalid entires can be removed by enabling hard enforce.")

    log("DONE", "Until next time.")


if __name__ == "__main__":
    main()