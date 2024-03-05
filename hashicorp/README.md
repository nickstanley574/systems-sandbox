# Hashicorp

**Goal:** Setup a 3 node Nomad, Consul and Vault cluster that will be both a server and agent node. This cluster should be reasonably secure requiring authentication to the clusters and the commination should be secured and the containers service should run not run a root.

**Current State**: Core Nomad TLS secured install completed.

**TODO**
- Setup Clients
- Consul
- Vault
- Enable Firewall
- Selinux ... maybe
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
    - Nomad - 1.7.4
    - Consul - TBD
    - Vault - TBD
    - Nginx -

Last Verified on

## Install Guide

TODO

### Local Hosts File

## Notes & Resources


**Annoying** - As of Feb 2024 `split()` Doesn't work in `.hcl` files despite `${env.ENV_VAR}` working.





