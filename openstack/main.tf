provider "openstack" {
}

data "openstack_images_image_v2" "image" {
  name = "CentOS-7-x64-2020-03"
}

data "openstack_compute_flavor_v2" "flavors" {
  for_each = local.instances
  name     = each.value.type
}

locals {
  instances = {
    for item in flatten([
      for key, value in var.instances : [
        for j in range(lookup(value, "count", 1)) : {
          (
            format("%s%d", key, j + 1)
            ) = {
            for key in setsubtract(keys(value), ["count"]) :
            key => value[key]
          }
        }
      ]
    ]) :
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
    for x, values in local.instances : x => true if contains(values.tags, "public") && !contains(keys(var.os_floating_ips), x)
  }
  pool = data.openstack_networking_network_v2.ext_network.name
}

locals {
  puppetmaster_ip = try(element([for x, values in local.instances : openstack_networking_port_v2.ports[x].all_fixed_ips[0] if contains(values.tags, "puppet")], 0), "")
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
    for_each = var.root_disk_size > data.openstack_compute_flavor_v2.flavors[each.key].disk ? [{ volume_size = var.root_disk_size }] : []
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
  volumes = merge([
    for ki, vi in var.storage : {
      for kj, vj in vi :
      "${ki}-${kj}" => {
        size     = vj
        instance = try(element([for x, values in local.instances : x if contains(values.tags, ki)], 0), null)
      }
    }
  ]...)
}

resource "openstack_blockstorage_volume_v2" "volumes" {
  for_each    = local.volumes
  name        = "${var.cluster_name}-${each.key}"
  description = "${var.cluster_name} ${each.key}"
  size        = each.value.size
}

resource "openstack_compute_volume_attach_v2" "attachments" {
  for_each    = { for k, v in local.volumes : k => v if v.instance != null }
  instance_id = openstack_compute_instance_v2.instances[each.value.instance].id
  volume_id   = openstack_blockstorage_volume_v2.volumes[each.key].id
}

locals {
  volume_devices = {
    for ki, vi in var.storage :
    ki => {
      for kj, vj in vi :
      kj => ["/dev/disk/by-id/*${substr(openstack_blockstorage_volume_v2.volumes["${ki}-${kj}"].id, 0, 20)}"]
    }
  }
}

locals {
  public_ip = merge(
    var.os_floating_ips,
    { for x, values in local.instances : x => openstack_networking_floatingip_v2.fip[x].address
    if contains(values.tags, "public") && !contains(keys(var.os_floating_ips), x) }
  )
}

resource "openstack_compute_floatingip_associate_v2" "fip" {
  for_each    = { for x, values in local.instances : x => true if contains(values.tags, "public") }
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

locals {
  mgmt1_ip        = try(openstack_networking_port_v2.ports["mgmt1"].all_fixed_ips[0], "")
  puppetmaster_id = try(element([for x, values in local.instances : openstack_compute_instance_v2.instances[x].id if contains(values.tags, "puppet")], 0), "")
  public_instances = { for x, values in local.instances :
    x => {
      public_ip   = openstack_compute_floatingip_associate_v2.fip[x].floating_ip
      internal_ip = openstack_networking_port_v2.ports[x].all_fixed_ips[0]
      tags        = values["tags"]
      id          = openstack_compute_instance_v2.instances[x].id
      hostkey     = ""
    }
    if contains(values.tags, "public")
  }

}
