#!/bin/bash

set -e

check_file_existence() {
    local file="$1"
    local max_attempts="$2"
    local wait_time="$3"

    for ((i=1; i<=$max_attempts; i++)); do
        if [ -e "$file" ]; then
            echo "File $file found. Continuing..."
            return 0  # Success
        else
            echo "File $file not found. Waiting $wait_time seconds (attempt $i/$max_attempts)..."
            sleep $wait_time
        fi

        if [ $i -eq $max_attempts ]; then
            echo "Maximum attempts reached. Exiting..."
            return 1  # Failure
        fi
    done
}

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

# vagrant up hashistack1

vagrant up hashistack1 hashistack2 hashistack3

echo "[$script_name] Done"

 