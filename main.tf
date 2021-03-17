provider "openstack" {
}

variable "cluster_name" {
  default = "hashy"
}

variable "root_disk_size" {
  default = 20
}

variable "os_floating_ips" {
  default = { }
}

variable "firewall_rules" {
  type    = list(
    object({
      name        = string
      from_port   = number
      to_port     = number
      ip_protocol = string
      cidr        = string
    })
  )
  default = [
    {
      "name"         = "SSH",
      "from_port"    = 22,
      "to_port"      = 22,
      "ip_protocol"  = "tcp",
      "cidr"         = "0.0.0.0/0"
    },
    {
      "name"         = "HTTP",
      "from_port"    = 80,
      "to_port"      = 80,
      "ip_protocol"  = "tcp",
      "cidr"         = "0.0.0.0/0"
    },
    {
      "name"         = "HTTPS",
      "from_port"    = 443,
      "to_port"      = 443,
      "ip_protocol"  = "tcp",
      "cidr"         = "0.0.0.0/0"
    },
    {
      "name"         = "Globus",
      "from_port"    = 2811,
      "to_port"      = 2811,
      "ip_protocol"  = "tcp",
      "cidr"         = "54.237.254.192/29"
    },
    {
      "name"         = "MyProxy",
      "from_port"    = 7512,
      "to_port"      = 7512,
      "ip_protocol"  = "tcp",
      "cidr"         = "0.0.0.0/0"
    },
    {
      "name"        = "GridFTP",
      "from_port"   = 50000,
      "to_port"     = 51000,
      "ip_protocol" = "tcp",
      "cidr"        = "0.0.0.0/0"
    }
  ]
  description = "List of login external firewall rules defined as map of 5 values name, from_port, to_port, ip_protocol and cidr"
}

resource "random_string" "puppetmaster_password" {
  length  = 32
  special = false
}

variable "os_ext_network" {
  type    = string
  default = null
}

variable "os_int_network" {
  type    = string
  default = null
}

variable "os_int_subnet" {
  type    = string
  default = null
}

variable "public_keys" {
  default = []
}

variable "instances" {
  description = "Map that defines the parameters for each type of instance of the cluster"
  default = {
    mgmt     = { type = "p4-6gb", tags = ["puppet", "mgmt", "storage"] },
    login    = { type = "p2-3gb", tags = ["login", "proxy", "public"] },
    node     = { type = "p2-3gb", tags = ["node"], count = 2 },
    # gpu      = { type = "g1-18gb-c4-22gb", tags = ["node"], count = 2  },
  }
}

data "openstack_images_image_v2" "image" {
  name = "CentOS-7-x64-2020-03"
}

data "openstack_compute_flavor_v2" "flavors" {
  for_each = local.instances
  name = each.value.type
}

locals {
  instances = {
    for item in flatten([
      for key, value in var.instances: [
        for j in range(lookup(value, "count", 1)): {
          (
            format("%s%d", key, j+1)
          ) = {
            for key in setsubtract(keys(value), ["count"]):
              key => value[key]
          }
        }
      ]
    ]):
    keys(item)[0] => values(item)[0]
  }
}

resource "openstack_compute_keypair_v2" "keypair" {
  name       = "${var.cluster_name}-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "openstack_compute_secgroup_v2" "secgroup" {
  name        = "${var.cluster_name}-secgroup"
  description = "MC security group"

  rule {
    from_port   = -1
    to_port     = -1
    ip_protocol = "icmp"
    self        = true
  }

  rule {
    from_port   = 1
    to_port     = 65535
    ip_protocol = "tcp"
    self        = true
  }

  rule {
    from_port   = 1
    to_port     = 65535
    ip_protocol = "udp"
    self        = true
  }

  dynamic "rule" {
    for_each = var.firewall_rules
    content {
      from_port   = rule.value.from_port
      to_port     = rule.value.to_port
      ip_protocol = rule.value.ip_protocol
      cidr        = rule.value.cidr
    }
  }

}

resource "openstack_networking_port_v2" "ports" {
  for_each           = local.instances
  name               = format("%s-%s-port", var.cluster_name, each.key)
  network_id         = local.network.id
  security_group_ids = [openstack_compute_secgroup_v2.secgroup.id]
  fixed_ip {
    subnet_id = local.subnet.id
  }
}

resource "openstack_networking_floatingip_v2" "fip" {
  for_each = {
    for x, values in local.instances: x => true if contains(values.tags, "public") && ! contains(keys(var.os_floating_ips), x)
  }
  pool = data.openstack_networking_network_v2.ext_network.name
}

locals {
  puppetmaster_ip = try(element([for x, values in local.instances: openstack_networking_port_v2.ports[x].all_fixed_ips[0] if contains(values.tags, "puppet")], 0), "")
}

data "template_cloudinit_config" "user_data" {
  for_each = local.instances
  part {
    filename     = "user_data.yaml"
    merge_type   = "list(append)+dict(recurse_array)+str()"
    content_type = "text/cloud-config"
    content      = templatefile("${path.module}/cloud-init/puppet.yaml",
      {
        tags                  = each.value.tags
        node_name             = format("%s", each.key),
        puppetenv_git         = "https://github.com/ComputeCanada/puppet-magic_castle.git",
        puppetenv_rev         = "10.2",
        puppetmaster_ip       = local.puppetmaster_ip,
        puppetmaster_password = random_string.puppetmaster_password.result,
        sudoer_username       = "centos",
        ssh_authorized_keys   = [file("~/.ssh/id_rsa.pub")],
      }
    )
  }
}

resource "openstack_compute_instance_v2" "instances" {
  for_each = local.instances
  name     = format("%s-%s", var.cluster_name, each.key)
  image_id = var.root_disk_size > data.openstack_compute_flavor_v2.flavors[each.key].disk ? null : data.openstack_images_image_v2.image.id

  flavor_name = each.value.type
  key_pair    = openstack_compute_keypair_v2.keypair.name
  user_data   = data.template_cloudinit_config.user_data[each.key].rendered

  network {
    port = openstack_networking_port_v2.ports[each.key].id
  }
  dynamic "network" {
    for_each = local.ext_networks
    content {
      access_network = network.value.access_network
      name           = network.value.name
    }
  }

  dynamic "block_device" {
    for_each = var.root_disk_size > data.openstack_compute_flavor_v2.flavors[each.key].disk ? [{volume_size = var.root_disk_size}] : []
    content {
      uuid                  = data.openstack_images_image_v2.image.id
      source_type           = "image"
      destination_type      = "volume"
      boot_index            = 0
      delete_on_termination = true
      volume_size           = block_device.value.volume_size
    }
  }

  lifecycle {
    ignore_changes = [
      image_id,
      block_device[0].uuid
    ]
  }
}

locals {
  public_ip = merge(
    var.os_floating_ips,
    {for x, values in local.instances: x => openstack_networking_floatingip_v2.fip[x].address
     if contains(values.tags, "public") && ! contains(keys(var.os_floating_ips), x)}
  )
}

resource "openstack_compute_floatingip_associate_v2" "fip" {
  for_each = {for x, values in local.instances: x => true if contains(values.tags, "public")}
  floating_ip = local.public_ip[each.key]
  instance_id = openstack_compute_instance_v2.instances[each.key].id
}


# locals {
#   instance_map = {
#     for key in keys(local.instances):
#       key => merge(
#         {
#           name      = format("%s-%s", var.cluster_name, key)
#           image_id  = data.openstack_images_image_v2.image.id,
#           port      = openstack_networking_port_v2.ports[key].id,
#           networks  = local.ext_networks,
#           root_disk = var.root_disk_size > data.openstack_compute_flavor_v2.flavors[key].disk ? [{volume_size = var.root_disk_size}] : []
#           user_data = data.template_cloudinit_config.user_data[key].rendered
#         },
#         local.node[key]
#     )
#   }
# }


output "public_instances" {
  value = {for x, values in local.instances: x => openstack_compute_floatingip_associate_v2.fip[x].floating_ip if contains(values.tags, "public")}
}