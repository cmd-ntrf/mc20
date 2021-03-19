variable "name" {
}

variable "vhosts" {
    type    = list(string)
    default = ["dtn", "ipa", "jupyter", "mokey"]
}

variable "public_instances" {}

data "external" "key2fp" {
  for_each = var.public_instances
  program = ["python", "${path.module}/key2fp.py"]
  query = {
    ssh_key = each.value["hostkeys"]["rsa"]
  }
}

locals {
    records = concat(
    [
        for key, values in var.public_instances: {
            type = "A"
            name = join(".", [key, var.name])
            value = values["public_ip"]
            data = null
        }
    ],
    flatten([
        for key, values in var.public_instances: [
            for vhost in var.vhosts:
            {
                type  = "A"
                name  = join(".", [vhost, var.name])
                value = values["public_ip"]
                data  = null
            }
        ]
        if contains(values["tags"], "proxy")
    ]),
    [
        for key, values in var.public_instances: {
            type  = "A"
            name  = var.name
            value = values["public_ip"]
            data  = null
        }
        if contains(values["tags"], "login")
    ],
    [
        for key, values in var.public_instances: {
            type  = "SSHFP"
            name  = join(".", [key, var.name])
            value = null
            data  = {
                algorithm   = data.external.key2fp[key].result["algorithm"]
                type        = 2
                fingerprint = data.external.key2fp[key].result["sha256"]
            }
        }
    ],
    # try([element([
    #     for key, values in var.public_instances: {
    #         type  = "SSHFP"
    #         name  = var.name
    #         value = null
    #         data  = {
    #             algorithm   = data.external.key2fp[key].result["algorithm"]
    #             type        = 2
    #             fingerprint = data.external.key2fp[key].result["sha256"]
    #         }
    #     } if contains(values["tags"], "login")
    # ], 0)], []),
    )
}

output "records" {
    value = local.records
}