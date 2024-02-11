# Hashicorp

**Goal:** Setup a 3 node Nomad, Consul and Vault cluster that will be both a server and agent node. This cluster should be reasonably secure requiring authentication to the clusters and the commination should be secured and the containers service should run not run a root.  

**Current State**: Core Nomad TLS secured install completed. 

**TODO**
- Split Nomad install into its own script for DRYness
- Enable ACL for Nomad
- Setup Clients
- Consul
- Vault
- Write guide once all above is complete.
- Write install guide
- Add Architecture Diagram
- Add video demo

## Design Overview

In a real prod setup each hashicorp service should be on their own dedicate single purpose cluster and masters should not be clients, clients are meant to be ephemeral since they are meant to dynamically scale. However I do not have a computer that can handle this.

## Versions

- Host
    - Ubuntu XXX
    - Vagrant 2.2.19 
    - [Vagrant Libvirt Provider](https://vagrant-libvirt.github.io/vagrant-libvirt/) 0.7.0-1
- Software versions
    - VagrantBox - [generic/ubuntu2204](https://app.vagrantup.com/generic/boxes/ubuntu2204)
    - Nomad - 
    - Consul - TBD
    - Vault - TBD
    - Nginx - 

Last Verified on  

## Install Guide

TODO

### Local Hosts File

## Notes & Resources

### Install & Init
- [Cluster Setup | hashicorp.com](https://developer.hashicorp.com/nomad/tutorials/cluster-setup/cluster-setup-aws)
- [Learn Nomad Cluster Setup | github.com/hashicorp](https://github.com/hashicorp/learn-nomad-cluster-setup/)
- [My First Nomad Cluster | thekevinwang.com](https://thekevinwang.com/2022/11/20/nomad-cluster)


**Annoying** - As of Feb 2024 `split()` Doesn't work in `.hcl` files despite `${env.ENV_VAR}` working. 


### Securing Nomad

#### ACL

TODO

#### TLS

- [hashicorp.com - TLS encryption for Nomad](https://developer.hashicorp.com/nomad/tutorials/transport-security/security-enable-tls)

    - Nomad requires all certificates be signed by the same Certificate Authority (CA). This should be a private CA and not a public one like Let's Encrypt.

    - You can use Nomad to generate the CA's private key and certificate. `nomad tls ca create`. The CA key (`nomad-agent-ca-key.pem`) will be used to sign certificates for Nomad agents and **must be kept private**. The CA certificate (`nomad-agent-ca.pem`) contains the public key necessary to validate Nomad certificates and must be distributed to every node that requires access.

    - TLS certificates commonly use the fully-qualified domain name of the system being identified as the certificate's Common Name (CN). However, hosts (therefore hostnames and IPs) are often ephemeral in Nomad clusters. Not only would signing a new certificate per Nomad node be difficult, but using a hostname provides no security or benefits to Nomad. **Due to this Nomad certificates are signed with their region.**

    - Commands
        - Generate a CA: `nomad tls ca create`
        - Generate a certificate for the Nomad client. `nomad tls cert create -client`
        - Generate a certificate for the CLI: `nomad tls cert create -cli`    

    - Each Nomad node should have the appropriate key (`-key.pem`) and certificate (`.pem`) file for its region and role. 

    - Each node needs the CA's public certificate (`nomad-agent-ca.pem`).

    - See [nomad.server.hcl](TIODO) and [nomad-client.hcl](TODO) for config comments



### Nginx Reverse Proxy
* https://developer.hashicorp.com/nomad/tutorials/manage-clusters/reverse-proxy-ui
* https://discuss.hashicorp.com/t/accessing-nomad-rest-api-ui-via-https/30812
* https://mpolinowski.github.io/docs/DevOps/Hashicorp/2022-05-24-hashicorp-nomad-with-nginx/2022-05-24/
* https://stackoverflow.com/questions/68421742/how-to-connect-to-the-nomad-consul-ui-with-tls-enabled
