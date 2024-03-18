#!/bin/bash

set -e

script_name=$(basename "$0")

create_nomad_certs=false

destroy=false

# Check command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c | --create-nomad-certs)
            create_nomad_certs=true
            ;;
        -d | --destroy)
            destroy=true
            ;;
        -n1)
            export CLUSTER_SIZE=1
            ;;
        -n3)
            export CLUSTER_SIZE=3
            ;;
        *)
            # Handle other arguments if needed
            ;;
    esac
    shift
done

vagrant --version

region=local

cert_types=(
    # Nomad CA
    "nomad-agent-ca-key.pem"
    "nomad-agent-ca.pem"
    # Nomad Server
    "$region-server-nomad-key.pem"
    "$region-server-nomad.pem"
    # Nomad Client
    "$region-client-nomad-key.pem"
    "$region-client-nomad.pem"
    # Nomad CLI
    "$region-cli-nomad-key.pem"
    "$region-cli-nomad.pem"
    # ssh keys
    "id_rsa_hashistack"
    "id_rsa_hashistack.pub"

)

CERT_VM_NAME=nomad-cert-creator


if [ "$create_nomad_certs" = true ]; then

    echo "[$script_name] Creating Nomad certificates..."

    CERT_CREATION=true vagrant up $CERT_VM_NAME

    CERT_CREATION=true vagrant ssh $CERT_VM_NAME -c "pwd; ls -al"

    echo "[$script_name] Saving created certs to generated_assets/"

    for cert in "${cert_types[@]}"; do
        echo "[$script_name] generated_assets/$cert"
        CERT_CREATION=true vagrant ssh $CERT_VM_NAME -c "sudo cat $cert" > generated_assets/$cert
    done



    # When running 'vagrant ssh -c "sudo cat id_rsa_hashistack,"' it adds a
    # carriage return ^M at the end of every line of the SSH key pairs for some
    # reason. Everything I read online says this occurs when transferring
    # Windows files to a Linux system, it's not the case here and I have not
    # found the root cause. This issue causes problems when using the keys
    # for SSH commands, such as the "Load key "id_rsa_hashistack": error in libcrypto."
    #
    # The below sed command removes the carriage return.

    sed -i 's/\r//g' generated_assets/id_rsa_hashistack generated_assets/id_rsa_hashistack.pub

    CERT_CREATION=true vagrant destroy $CERT_VM_NAME -f

    echo "[$script_name] Nomad certificates creation completed."

    exit 0

fi

# for cert in "${cert_types[@]}"; do
#     if [ ! -e "certificates/$cert" ]; then
#         echo "Nomad '$cert' not found. If this is your first time running please use --create-nomad-certs."
#         exit 1
#     fi
# done


if [ "$destroy" = true ]; then
    CLUSTER_SIZE=3 vagrant destroy -f
    CERT_CREATION=true vagrant destroy $CERT_VM_NAME -f
else
    # Check if the ENV Var CLUSTER_SIZE is set
    if [ -z "$CLUSTER_SIZE" ]; then
        echo "[$script_name] INFO: CLUSTER_SIZE is not set. Defaulting to 1."
        CLUSTER_SIZE=1
    fi

    touch hashistack.log
    # Check the value of CLUSTER_SIZE
    if [ "$CLUSTER_SIZE" -eq 1 ]; then
        echo "[$script_name] CLUSTER_SIZE is 1"
        vagrant up hashistack1 | tee -a hashistack.log
    elif [ "$CLUSTER_SIZE" -eq 3 ]; then
        echo "[$script_name] CLUSTER_SIZE is 3"
        vagrant up hashistack1 hashistack2 hashistack3 | tee -a hashistack.log
    else
        echo "[$script_name] ERROR: CLUSTER_SIZE must be either 1 or 3."
        exit 1
    fi

    while true; do
        read -p "[$script_name] Waiting to destroy cluster (yes/no): " choice
        case $choice in
            [Yy]|[Yy][Ee][Ss])
                CLUSTER_SIZE=3 vagrant destroy -f
                break
                ;;
            [Nn]|[Nn][Oo])
                echo "[$script_name] Exiting..."
                exit 1
                ;;
            *)
                echo "[$script_name] Invalid input. Please enter 'yes' or 'no'."
                ;;
        esac
    done

fi

echo "[$script_name] Done"
