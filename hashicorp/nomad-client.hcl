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