import yaml
import os
import sys
import subprocess
import difflib
import json
import time
import hashlib

from ldapActions import *

with open('ldap_config.yaml') as file:
    ldap_cfg_file = yaml.load(file, Loader=yaml.FullLoader)

user_dir = f"{os.environ['CACHED_DIR']}/.users"
groups_dir = f"{os.environ['CACHED_DIR']}/.groups"

if not os.path.exists(user_dir):
    os.makedirs(user_dir)

if not os.path.exists(groups_dir):
    os.makedirs(groups_dir)


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
        create_group(group)
        f = open(grouppath, "x")
        f.close()


groupsfiles = os.listdir(groups_dir)
for f in groupsfiles:
    if f not in active_groups:
        delete_group(f)
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
        current_md5 = user_filepath.split('-')[1]
        create_user(cfg_user_eip, cfg_user_uid)
        enforce_groups(cfg_user_uid, cfg_user_groups)
        f = open(user_filepath, "x")
        f.close()

    # Modify Current User
    elif cfg_user_md5 not in all_userfiles_m5d:
        current_file = usersfile_dict[str(cfg_user_eip)]['file']
        file_user_uid = usersfile_dict[str(cfg_user_eip)]['uid']

        if file_user_uid != cfg_user_uid:
            os.system(f"smbldap-usermod --rename {cfg_user_uid} {file_user_uid}")
        else:
            enforce_groups(cfg_user_uid, cfg_user_groups)

        os.remove(f"{user_dir}/{current_file}")
        f = open(user_filepath, "x")
        f.close()

# Delete Users
for user_files in all_users_files:
    eip, m5, uid = user_files.split("-")
    if int(eip) not in ldap_cfg_file['users'].keys():
        print(f"Delete: {user_files}")
        delete_user(uid)
        os.remove(f"{user_dir}/{user_files}")
