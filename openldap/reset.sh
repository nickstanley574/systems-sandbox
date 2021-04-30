vagrant box update
vagrant destroy -f
sleep 1
vagrant up centosldap
echo "--ssh--"
vagrant ssh -c 'sudo su; /bin/bash; cd /vagrant/'