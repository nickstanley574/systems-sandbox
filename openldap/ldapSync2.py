import yaml, os, sys, subprocess
import difflib
import json, time
import hashlib

from ldapActions import *

with open('ldap_config.yaml') as file:
    ldap_config_file = yaml.load(file, Loader=yaml.FullLoader)

user_dir = f"{os.environ['CACHED_DIR']}/.users"

if not os.path.exists(user_dir):
    os.makedirs(user_dir)
usersfiles = os.listdir(user_dir)


usersfileseip = []
usersfilesm5 = []
usersfileuid = []

usersfile_dict = {}

for i in usersfiles:
    eip, m5 = i.split("-")
    # uid = ldap_config_file['users'][int(eip)]['ldap']['uid']
    usersfileseip.append(eip)
    usersfilesm5.append(m5)
    usersfile_dict[eip] = {
        'file':i,
        'm5':m5
    }
    # usersfileuid.append(uid)

new_users = []
modified_users = []
active_eips = []
roles = ldap_config_file['roles']


for user_eip in ldap_config_file['users']:
    newuser_uid = ldap_config_file['users'][user_eip]['ldap']['uid']
    user_m5 = hashlib.md5(json.dumps(ldap_config_file['users'][user_eip]).encode()).hexdigest()
    userfile = f"{user_eip}-{user_m5}"
    userpath = f"{user_dir}/{userfile}"
    active_eips.append(user_eip)

    if str(user_eip) not in usersfileseip:
        print(f"Create: {userfile} ({newuser_uid})")
        current_m5 = userpath.split('-')[1]
        create_user(user_eip, newuser_uid)
        f = open(userpath, "x")
        f.close()

    elif user_m5 not in usersfilesm5:
        oldfile = usersfile_dict[str(user_eip)]['file']
        print(f"Modify:")
        print(f"   old: {oldfile} ({newuser_uid})")
        print(f"   new: {userfile} ({newuser_uid})")

        f = open(userpath, "x")
        os.remove(f"{user_dir}/{user}")
        f.close()

for user in usersfiles:
    eip = user.split("-")[0]
    if int(eip) not in active_eips:
        print(f"Delete: {user}")
        os.remove(f"{user_dir}/{user}")


