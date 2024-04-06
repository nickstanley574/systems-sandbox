#/bin/bash

ssh-keygen -f "/home/nick/.ssh/known_hosts" -R "172.16.8.10"

printf "\nDashboard Token:\n"
ssh -o StrictHostKeyChecking=no -i id_rsa_k8 root@172.16.8.10 \
    "source ~/.profile; kubectl -n kubernetes-dashboard create token admin-user"
printf "\n\n"

LOCAL_PORT=10443

printf "\n\nhttps://localhost:$LOCAL_PORT\n\n"

# https://www.baeldung.com/linux/ctrlc-ssh-connection
# <(cat; kill -INT 0)
# Workaround for terminating remote tasks via SSH where SIGINT isn't passed:
# Using process substitution to feed command input from 'cat', ensuring
# sequential execution of 'kill -INT 0' to terminate all processes sharing
# the same process group ID (PGID), useful for scenarios involving process
# forking like with stress-ng.
ssh -o StrictHostKeyChecking=no  -i id_rsa_k8 -L $LOCAL_PORT:127.0.0.1:$LOCAL_PORT root@172.16.8.10 \
    "source ~/.profile; kubectl port-forward svc/kubernetes-dashboard -n kubernetes-dashboard $LOCAL_PORT:443 < <(cat; kill -INT 0)"

