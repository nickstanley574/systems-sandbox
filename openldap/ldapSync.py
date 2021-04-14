import yaml, os, sys, subprocess


with open(r'ldap.yaml') as file:
    ldap_config_file = yaml.load(file, Loader=yaml.FullLoader)


def display(title, message):
    print(f"{title:<14} - {message}")


def smbldap_output_to_list(output):
    return list(filter(None,output.decode().replace(" ", "").split('\n')))


def create_group(groupname):
    display("Create Group", groupname)
    os.system(f"smbldap-groupadd -a {groupname}")


def enforce_groups(uid, groups):
    groups =  ','.join(list(groups))
    display("Enforce Groups", f"{uid} member of {groups}")
    exitcode = os.WEXITSTATUS(os.system(f'smbldap-usermod -G {groups} {uid}'))
    if exitcode != 0:
        print(f"Something is wrong with {uid} groups {groups}.")
        sys.exit(2)


def delete_group(groupname):
    display("Delete Group", groupname)
    os.system(f"smbldap-groupdel {groupname} ")


def create_user(ein, uid):
    display("Create User",uid)
    exitcode = os.WEXITSTATUS(os.system(f"smbldap-useradd {uid} -Z employeeNumber={ein}"))
    if exitcode != 0:
        print(f"Create user {uid} failed.")
        sys.exit(2)


def delete_user(uid):
    display("Delete User", uid)
    os.system(f"smbldap-userdel {uid}")


def get_all_groups():
    return smbldap_output_to_list(
        subprocess.check_output(f"smbldap-grouplist | cut -d'|' -f2 | tail -n +3", shell=True))


def get_current_users():
    return smbldap_output_to_list(
        subprocess.check_output(f"smbldap-userlist | cut -d'|' -f2 | tail -n +3", shell=True))


def get_current_users_detailed():
    result = {}
    for user in get_current_users():
        result.update(get_user_info(user))
    return result


def get_user_info(user):
    employee, details = {}, {}
    for item in smbldap_output_to_list(subprocess.check_output(f"smbldap-usershow {user}", shell=True)):
        key, value = item.split(":")
        if key == 'employeeNumber':
            ein = value
        else:
            details[key] = value
    employee[ein] = details
    return employee


def get_config_groups():
    config_groups = ldap_config_file['groups']
    for rolename in ldap_config_file['roles']:
        config_groups.append(f"role-{rolename}")
    return config_groups


#####################################################################################


print("Starting LDAP sync...\n")

print("PRECHECKS")
print("Done.\n")


print("GROUPS/ROLES")
current_groups = get_all_groups()
config_groups = get_config_groups()

# Delete Groups no longer in the ldap config
for group in current_groups:
    if group not in config_groups:
        delete_group(group)

# Add Groups that are in the ldap config but not in ldap
for group in ldap_config_file['groups']:
    if group not in current_groups:
        create_group(group)

for rolename in ldap_config_file['roles']:
    rolename = f"role-{rolename}"
    if rolename not in current_groups:
        create_group(rolename)
print("Done.\n")



print("USERS")
current_users = get_current_users_detailed()
users_in_config = []

# Loop overall all users in the config file
for ein, details in ldap_config_file['users'].items():
    users_in_config.append(ldap_config_file['users'][ein]['ldap']['uid'])
    ein = str(ein)

    # If config users is not in ldap add them
    if ein not in current_users.keys():
        newuser_uid = details['ldap']['uid']
        create_user(ein, newuser_uid)
        current_users.update(get_user_info(newuser_uid))

    # Update Current Users
    for key in details['ldap'].keys():
        value = details['ldap'][key]
        if key not in current_users[ein].keys() or value != current_users[ein][key]:
            user_uid = current_users[ein]['uid']
            if key == 'uid':
                os.system(f"smbldap-usermod --rename {value} {user_uid}")
            else:
                print(f"Updating {user_uid} {key}={value} ")
                os.system(f"smbldap-usermod -Z {key}={value} {user_uid}")

    # Enforce User Group Memberships
    user_group_membership = []
    for role in details['roles']:
        user_group_membership += ldap_config_file['roles'][role]
        user_group_membership.append(f"role-{role}")
    enforce_groups(details['ldap']['uid'],set(user_group_membership))

# Delete users that are not in the ldap config file.
for user in get_current_users():
    if user not in users_in_config:
        delete_user(user)
print("Done.\n")


print("LDAP Sync Complete.")