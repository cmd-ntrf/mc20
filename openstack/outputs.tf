
output "public_instances" {
  value = {for x, values in local.instances: x => openstack_compute_floatingip_associate_v2.fip[x].floating_ip if contains(values.tags, "public")}
}
