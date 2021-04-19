vagrant destroy -f
sleep 1
vagrant up centosldap
sleep 1
echo "--ssh--"
vagrant ssh -c 'sudo su; /bin/bash; cd /vagrant/'