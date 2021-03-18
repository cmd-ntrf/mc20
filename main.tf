terraform {
  required_version = ">= 0.13.4"
}

module "openstack" {
  source         = "./openstack"
  config_git_url = "https://github.com/ComputeCanada/puppet-magic_castle.git"
  config_version = "nfs-glob"

  cluster_name = "hashi"
  domain       = "calculquebec.cloud"
  image        = "CentOS-7-x64-2020-03"

  instances = {
    puppet = { type = "p4-6gb", tags = ["puppet"] }
    mgmt   = { type = "p4-6gb", tags = ["mgmt", "nfs"] }
    login  = { type = "p2-3gb", tags = ["login", "proxy", "public"] }
    node   = { type = "p2-3gb", tags = ["node"], count = 2 }
    # gpu      = { type = "g1-18gb-c4-22gb", tags = ["node"], count = 2  },
  }

  storage = {
    nfs = {
      home     = 50
      project  = 100
      scratch  = 100
      software = 10
    }
  }

  public_keys = [file("~/.ssh/id_rsa.pub")]

  nb_users = 10
  # Shared password, randomly chosen if blank
  guest_passwd = ""

  # OpenStack specific
  os_floating_ips = {}
}

output "public_instances" {
  value = module.openstack.public_instances
}

## Uncomment to register your domain name with CloudFlare
module "dns" {
  source           = "./dns/cloudflare"
  email            = "you@example.com"
  name             = module.openstack.cluster_name
  domain           = module.openstack.domain
  public_instances = module.openstack.public_instances
  ssh_private_key  = module.openstack.ssh_private_key
  sudoer_username  = module.openstack.sudoer_username
}

## Uncomment to register your domain name with Google Cloud
# module "dns" {
#   source           = "git::https://github.com/ComputeCanada/magic_castle.git//dns/gcloud"
#   email            = "you@example.com"
#   project          = "your-project-id"
#   zone_name        = "you-zone-name"
#   name             = module.openstack.cluster_name
#   domain           = module.openstack.domain
#   public_ip        = module.openstack.ip
#   login_ids        = module.openstack.login_ids
#   rsa_public_key   = module.openstack.rsa_public_key
#   ssh_private_key  = module.openstack.ssh_private_key
#   sudoer_username  = module.openstack.sudoer_username
# }

# output "hostnames" {
#   value = module.dns.hostnames
# }
