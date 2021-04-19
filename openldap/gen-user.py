import random


roles = ['developer','sdet']


n = 0
for number in range(1000,3000):
    uid = f"test.user{n}"
    role = roles[random.randrange(len(roles))]
    forstr = f"""\
  {number}:
    ldap:
      uid: {uid}
      mail: {uid}@example.com
    roles:
      - {role}"""
    print(forstr)
    n+=1


