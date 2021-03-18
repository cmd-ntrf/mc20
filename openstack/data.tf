resource "random_string" "munge_key" {
  length  = 32
  special = false
}

resource "random_string" "puppetmaster_password" {
  length  = 32
  special = false
}

resource "random_string" "freeipa_passwd" {
  length  = 16
  special = false
}

resource "random_pet" "guest_passwd" {
  length    = 4
  separator = "."
}

resource "random_uuid" "consul_token" {}

data "http" "hieradata_template" {
  url = "${replace(var.config_git_url, ".git", "")}/raw/${var.config_version}/data/terraform_data.yaml.tmpl"
}

data "template_file" "hieradata" {
  template = data.http.hieradata_template.body

  vars = {
    sudoer_username = var.sudoer_username
    freeipa_passwd  = random_string.freeipa_passwd.result
    cluster_name    = lower(var.cluster_name)
    domain_name     = var.domain
    guest_passwd    = random_pet.guest_passwd.id
    consul_token    = random_uuid.consul_token.result
    munge_key       = base64sha512(random_string.munge_key.result)
    nb_users        = var.nb_users
    mgmt1_ip        = local.mgmt1_ip
    home_dev        = jsonencode(local.volume_devices["nfs"]["home"])
    project_dev     = jsonencode(local.volume_devices["nfs"]["project"])
    scratch_dev     = jsonencode(local.volume_devices["nfs"]["scratch"])
  }
}

data "http" "facts_template" {
  url = "${replace(var.config_git_url, ".git", "")}/raw/${var.config_version}/site/profile/facts.d/terraform_facts.yaml.tmpl"
}

data "template_file" "facts" {
  template = data.http.facts_template.body

  vars = {
    software_stack = "computecanada"
    cloud_provider = "openstack"
    cloud_region   = "arbutus"
  }
}

data "template_cloudinit_config" "user_data" {
  for_each = local.instances
  part {
    filename     = "user_data.yaml"
    merge_type   = "list(append)+dict(recurse_array)+str()"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-init/puppet.yaml",
      {
        tags                  = each.value.tags
        node_name             = format("%s", each.key),
        puppetenv_git         = "https://github.com/ComputeCanada/puppet-magic_castle.git",
        puppetenv_rev         = "nfs-glob",
        puppetmaster_ip       = local.puppetmaster_ip,
        puppetmaster_password = random_string.puppetmaster_password.result,
        sudoer_username       = "centos",
        ssh_authorized_keys   = [file("~/.ssh/id_rsa.pub")],
      }
    )
  }
}

resource "null_resource" "deploy_hieradata" {
  connection {
    type         = "ssh"
    bastion_host = local.public_ip[keys(local.public_ip)[0]]
    bastion_user = var.sudoer_username
    user         = var.sudoer_username
    host         = "puppet"
  }

  triggers = {
    hieradata = md5(data.template_file.hieradata.rendered)
    facts     = md5(data.template_file.facts.rendered)
  }

  provisioner "file" {
    content     = data.template_file.hieradata.rendered
    destination = "terraform_data.yaml"
  }

  provisioner "file" {
    content     = data.template_file.facts.rendered
    destination = "terraform_facts.yaml"
  }

  provisioner "file" {
    content     = "---"
    destination = "user_data.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/puppetlabs/data",
      "sudo mkdir -p /etc/puppetlabs/facts",
      "sudo install -m 650 terraform_data.yaml user_data.yaml /etc/puppetlabs/data/",
      "sudo install -m 650 terraform_facts.yaml /etc/puppetlabs/facts/",
      # These chgrp commands do nothing if the puppet group does not yet exist
      # so these are also handled by puppetmaster.yaml
      "sudo chgrp puppet /etc/puppetlabs/data/terraform_data.yaml /etc/puppetlabs/data/user_data.yaml &> /dev/null || true",
      "sudo chgrp puppet /etc/puppetlabs/facts/terraform_facts.yaml &> /dev/null || true",
      "rm -f terraform_data.yaml user_data.yaml terraform_facts.yaml",
    ]
  }
}
