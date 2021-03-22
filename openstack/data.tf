locals {
  domain_name = "${lower(var.cluster_name)}.${lower(var.domain)}"
  instances = merge(
    flatten([
      for hostname, attrs in var.instances : [
        for i in range(lookup(attrs, "count", 1)) : {
          (format("%s%d", hostname, i + 1)) = { for attr, value in attrs : attr => value if attr != "count" }
        }
      ]
    ])...
  )
  host2prefix =  merge(
    flatten([
      for hostname, attrs in var.instances : [
        for i in range(lookup(attrs, "count", 1)) : {
          (format("%s%d", hostname, i + 1)) = hostname
        }
      ]
    ])...
  )
}

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
  count     = var.guest_passwd != "" ? 0 : 1
  length    = 4
  separator = "."
}

resource "random_uuid" "consul_token" {}

resource "tls_private_key" "ssh" {
  count     = var.generate_ssh_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_private_key" "rsa_hostkeys" {
  for_each  = toset(keys(var.instances))
  algorithm = "RSA"
  rsa_bits  = 4096
}

data "http" "hieradata_template" {
  url = "${replace(var.config_git_url, ".git", "")}/raw/${var.config_version}/data/terraform_data.yaml.tmpl"
}

data "template_file" "hieradata" {
  template = data.http.hieradata_template.body

  vars = {
    sudoer_username = var.sudoer_username
    freeipa_passwd  = random_string.freeipa_passwd.result
    cluster_name    = lower(var.cluster_name)
    domain_name     = local.domain_name
    guest_passwd    = var.guest_passwd != "" ? var.guest_passwd : try(random_pet.guest_passwd[0].id, "")
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

locals {
  user_data = {
    for key, values in local.instances: key =>
    templatefile("${path.module}/cloud-init/puppet.yaml",
      {
        tags                  = values["tags"]
        node_name             = key,
        puppetenv_git         = var.config_git_url,
        puppetenv_rev         = var.config_version,
        puppetmaster_ip       = local.puppetmaster_ip,
        puppetmaster_password = random_string.puppetmaster_password.result,
        sudoer_username       = var.sudoer_username,
        ssh_authorized_keys   = var.public_keys,
        hostkeys = {
          rsa = {
            private = tls_private_key.rsa_hostkeys[local.host2prefix[key]].private_key_pem
            public  = tls_private_key.rsa_hostkeys[local.host2prefix[key]].public_key_openssh
          }
        }
      }
    )
  }
}

locals {
  all_tags = flatten([for key, values in local.instances : values["tags"]])
}

resource "null_resource" "deploy_hieradata" {
  count = contains(local.all_tags, "puppet") && contains(local.all_tags, "public") ? 1 : 0

  connection {
    type                = "ssh"
    bastion_host        = local.public_ip[keys(local.public_ip)[0]]
    bastion_user        = var.sudoer_username
    bastion_private_key = try(tls_private_key.ssh[0].private_key_pem, null)
    user                = var.sudoer_username
    host                = "puppet"
    private_key         = try(tls_private_key.ssh[0].private_key_pem, null)
  }

  triggers = {
    user_data    = md5(var.hieradata)
    hieradata    = md5(data.template_file.hieradata.rendered)
    facts        = md5(data.template_file.facts.rendered)
    puppetmaster = local.puppetmaster_id
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
    content     = var.hieradata
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

