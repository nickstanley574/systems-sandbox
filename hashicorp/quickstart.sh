#!/bin/bash

set -e

script_name=$(basename "$0")

create_nomad_certs=false

# Check command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c | --create-nomad-certs)
            create_nomad_certs=true
            ;;
        *)
            # Handle other arguments if needed
            ;;
    esac
    shift
done

vagrant --version

cert_types=( 
    # Nomad CA
    "nomad-agent-ca-key.pem"
    "nomad-agent-ca.pem"
    # Nomad Server
    "global-server-nomad-key.pem"
    "global-server-nomad.pem"
    # Nomad Client
    "global-client-nomad-key.pem"
    "global-client-nomad.pem"
    # Nomad CLI
    "global-cli-nomad-key.pem"
    "global-cli-nomad.pem"
)

if [ "$create_nomad_certs" = true ]; then

    echo "[$script_name] Creating Nomad certificates..."

    CERT_VM_NAME=nomad-cert-creator

    CERT_CREATION=true vagrant up $CERT_VM_NAME

    CERT_CREATION=true vagrant ssh $CERT_VM_NAME -c "pwd; ls -al"

    echo "[$script_name] Saving created certs to certificates/"
    for cert in "${cert_types[@]}"; do
        echo "[$script_name] certificates/$cert"
        CERT_CREATION=true vagrant ssh $CERT_VM_NAME -c "sudo cat $cert" > certificates/$cert
    done

    CERT_CREATION=true vagrant destroy $CERT_VM_NAME -f
    
    echo "[$script_name] Nomad certificates creation completed." 

fi

# for cert in "${cert_types[@]}"; do
#     if [ ! -e "certificates/$cert" ]; then
#         echo "Nomad '$cert' not found. If this is your first time running please use --create-nomad-certs."
#         exit 1
#     fi
# done


# Check if the ENV Var CLUSTER_SIZE is set
if [ -z "$CLUSTER_SIZE" ]; then
    echo "[$script_name] INFO: CLUSTER_SIZE is not set. Defaulting to 1."
    CLUSTER_SIZE=1
fi

# Check the value of CLUSTER_SIZE
if [ "$CLUSTER_SIZE" -eq 1 ]; then
    echo "[$script_name] CLUSTER_SIZE is 1"
    vagrant up hashistack1
elif [ "$CLUSTER_SIZE" -eq 3 ]; then
    echo "[$script_name] CLUSTER_SIZE is 3"
    vagrant up hashistack1 hashistack2 hashistack3
else
    echo "[$script_name] ERROR: CLUSTER_SIZE must be either 1 or 3."
    exit 1
fi





while true; do
    read -p "Waiting to destroy cluster (yes/no): " choice
    case $choice in
        [Yy]|[Yy][Ee][Ss]) 
            vagrant destroy -f
            break
            ;;
        [Nn]|[Nn][Oo])
            echo "Exiting..."
            exit 1
            ;;
        *)
            echo "Invalid input. Please enter 'yes' or 'no'."
            ;;
    esac
done


echo "[$script_name] Done"

 