#!/bin/bash
vagrant --version

# CERT_VM_NAME=nomad-cert-creator

# vagrant up $CERT_VM_NAME

# cert_types=( 
#     # CA
#     "nomad-agent-ca-key.pem"
#     "nomad-agent-ca.pem"
    
#     # Server
#     "global-server-nomad-key.pem"
#     "global-server-nomad.pem"

#     # Client
#     "global-client-nomad-key.pem"
#     "global-client-nomad.pem"

#     #CLI
#     "global-cli-nomad-key.pem"
#     "global-cli-nomad.pem"
# )

# for cert in "${cert_types[@]}"; do
#     vagrant ssh $CERT_VM_NAME -c "sudo cat $cert" > certificates/$cert
# done

# vagrant destroy $CERT_VM_NAME -f

# sleep 3

vagrant up hashistack1 hashistack2 hashistack3

sleep 5

 