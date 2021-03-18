variable "name" {
}

variable "vhosts" {
    type    = list(string)
    default = ["dtn", "ipa", "jupyter", "mokey"]
}

variable "public_instances" {}

# data "external" "key2fp" {
#   program = ["python", "${path.module}/key2fp.py"]
#   query = {
#     ssh_key = var.rsa_public_key
#   }
# }

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
    ])
    )
}

output "records" {
    value = local.records
}

# locals {
#     name_A = [
#         for ip in var.login_ips : {
#             type  = "A"
#             name  = var.name
#             value = ip
#             data  = null
#         }
#     ]
#     login_A = [
#         for index in range(length(var.login_ips)) : {
#             type  = "A"
#             name  = join(".", [format("login%d", index + 1), var.name])
#             value = var.login_ips[index]
#             data  = null
#         }
#     ]
#     jupyter_A = [
#         for ip in var.login_ips : {
#             type  = "A"
#             name  = join(".", ["jupyter", var.name])
#             value = ip
#             data  = null
#         }
#     ]
#     ipa_A = [
#         for ip in var.login_ips : {
#             type  = "A"
#             name  = join(".", ["ipa", var.name])
#             value = ip
#             data  = null
#         }
#     ]
#     dtn_A = [
#         for ip in var.login_ips : {
#             type  = "A"
#             name  = join(".", ["dtn", var.name])
#             value = ip
#             data  = null
#         }
#     ]
#     mokey_A = [
#         for ip in var.login_ips : {
#             type  = "A"
#             name  = join(".", ["mokey", var.name])
#             value = ip
#             data  = null
#         }
#     ]
#     name_SSHFP = [
#         {
#             type  = "SSHFP"
#             name  = var.name
#             value = null
#             data  = {
#                 algorithm   = data.external.key2fp.result["algorithm"]
#                 type        = 2
#                 fingerprint = data.external.key2fp.result["sha256"]
#             }
#         }
#     ]
#     login_SSHFP = [
#         for index in range(length(var.login_ips)) : {
#             type  = "SSHFP"
#             name  = join(".", [format("login%d", index + 1), var.name])
#             value = null
#             data  = {
#                 algorithm   = data.external.key2fp.result["algorithm"]
#                 type        = 2
#                 fingerprint = data.external.key2fp.result["sha256"]
#             }
#         }
#     ]
# }

# output "records" {
#     value = concat(
#         local.name_A,
#         local.login_A,
#         local.jupyter_A,
#         local.ipa_A,
#         local.dtn_A,
#         local.mokey_A,
#         local.name_SSHFP,
#         local.login_SSHFP
#     )
# }