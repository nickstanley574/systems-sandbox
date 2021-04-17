import yaml, os, sys, subprocess
import time




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
    # if exitcode != 0:
    #     print(f"Create user {uid} failed.")
    #     sys.exit(2)


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


