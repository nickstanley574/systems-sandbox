# Hashicorp

## Goal 

Setup a 3 node nomad, consul and vault cluster that will be both a server and agent node. This cluster should be reasonably secure requiring authentication to the clusters and the commination should be secured and the containers service should run not run a root.  

### 

In a real prod setup each hashicorp service should be on their own dedicate single purpose cluster and masters should not be clients, clients are meant to be ephemeral  since they are meant to dynamically scale. However I do not have a computer that can handle this. Since the goal is to show a config of masters and how the configs can be setup to high avaluabley and how a cluster can recover then a istance does down.  

## Built on 

Host
Ubuntu XXX
Vagrant 2.2.19 

Using lvirt - explain why
Vagrant Box

Nomad
Consul
Vault


## Annoying 

`split()` Doesn't work in `.hcl` files despite `${env.ENV_VAR}` working. 

## Resources And Notes

### Install & Init
- https://developer.hashicorp.com/nomad/tutorials/cluster-setup/cluster-setup-aws
- https://github.com/hashicorp/learn-nomad-cluster-setup/blob/main/shared/config/nomad.hcl
- https://thekevinwang.com/2022/11/20/nomad-cluster

### Running Job With Podman
- https://developer.hashicorp.com/nomad/plugins/drivers/podman

### Securing Nomad

#### ACL

#### TLS

- https://developer.hashicorp.com/nomad/tutorials/transport-security/security-enable-tls
    
    - Nomad requires all certificates be signed by the same Certificate Authority (CA). This should be a private CA and not a public one like Let's Encrypt.
    
    - You can use Nomad to generate the CA's private key and certificate. `nomad tls ca create`. The CA key (`nomad-agent-ca-key.pem`) will be used to sign certificates for Nomad agents and **must be kept private**. The CA certificate (`nomad-agent-ca.pem`) contains the public key necessary to validate Nomad certificates and must be distributed to every node that requires access.

    - TLS certificates commonly use the fully-qualified domain name of the system being identified as the certificate's Common Name (CN). However, hosts (and therefore hostnames and IPs) are often ephemeral in Nomad clusters. Not only would signing a new certificate per Nomad node be difficult, but using a hostname provides no security or functional benefits to Nomad. To fulfill the desired security properties Nomad certificates are signed with their region.

    - Commands:
        - Generate a CA: `nomad tls ca create`
            - `nomad-agent-ca-key.pem` - **CA private key. Keep safe.**
            - `nomad-agent-ca.pem` - CA public certificate.

        - Generate a certificate for the Nomad server: `nomad tls cert create -server -region global`
            - `global-server-nomad-key.pem` - Nomad server node private key for the `global` region.
            - `global-server-nomad.pem` - Nomad server node public certificate for the `global` region.

        - Generate a certificate for the Nomad client. `nomad tls cert create -client`
            - `global-client-nomad-key.pem` - Nomad client node private key for the `global` region.
            - `global-client-nomad.pem` - Nomad client node public certificate for the `global` region.
    
        - Generate a certificate for the CLI: `nomad tls cert create -cli`    
            - `global-cli-nomad-key.pem` - Nomad CLI private key for the `global` region.
            - `global-cli-nomad.pem` - Nomad CLI certificate for the `global` region.


    - Each Nomad node should have the appropriate key (`-key.pem`) and certificate (`.pem`) file for its region and role. In addition each node needs the CA's public certificate (`nomad-agent-ca.pem`).

    - 
    ```
    # Require TLS Server
    tls {

        # This enables TLS for the HTTP and RPC protocols. Nomad doesn't
        # use separate ports for TLS and non-TLS traffic: your cluster 
        # should either use TLS or not.
        http = true
        rpc  = true

        # The file lines should point to wherever you placed the certificate files on the node.
        # This tutorial assumes they are in Nomad's current directory.
        ca_file   = "nomad-agent-ca.pem"
        cert_file = "global-server-nomad.pem"
        key_file  = "global-server-nomad-key.pem"

        # If verify_server_hostname is set to false the node's certificate
        # will be checked to ensure it is signed by the same CA, but its
        # role and region will not be verified. This means any service
        # with a certificate signed by same CA as Nomad can act as a client
        # or server of any region.
        verify_server_hostname = true
        verify_https_client    = true
    }
    ```

    - 
    ```
    # Require TLS
    tls {
        http = true
        rpc  = true

        # The Nomad client configuration is similar to the server configuration.
        # The biggest difference is in the certificate and key used for configuration.
        ca_file   = "nomad-agent-ca.pem"
        cert_file = "global-client-nomad.pem"
        key_file  = "global-client-nomad-key.pem"

        verify_server_hostname = true
        verify_https_client    = true
    }
    ```

    Nginx Reverse Proxy - 
    https://developer.hashicorp.com/nomad/tutorials/manage-clusters/reverse-proxy-ui
    https://discuss.hashicorp.com/t/accessing-nomad-rest-api-ui-via-https/30812
    https://mpolinowski.github.io/docs/DevOps/Hashicorp/2022-05-24-hashicorp-nomad-with-nginx/2022-05-24/
    https://stackoverflow.com/questions/68421742/how-to-connect-to-the-nomad-consul-ui-with-tls-enabled

    Because of best practices around least access to nodes, it is typical for Nomad UI users to not have direct access to the Nomad client nodes.



    https://medium.com/navin-nair/practical-hashicorp-nomad-and-consul-a-little-more-than-hello-world-part-1-991d2a54fd64



