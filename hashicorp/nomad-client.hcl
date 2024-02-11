# Follower config file
datacenter = "vagrant"
data_dir   = "/opt/nomad/data"
bind_addr  = "0.0.0.0"

client {
  enabled = true
  servers = [
      "hashistack1.vagrant",
      "hashistack2.vagrant",
      "hashistack3.vagrant",
  ]
}


# If verify_server_hostname is set to false, the client's certificate will
    # be checked to ensure it is signed by the same CA, but its role and region
    # will not be verified. This allows flexibility in client configuration.