variable "name" {
}

variable "domain" {
}

variable "email" {
}

variable "sudoer_username" {
}

variable "domain_tag" {
  description = "Indicate which public instances should be pointed by the domain name A record."
  default     = "login"
}

variable "vhost_tag" {
  description = "Indicate which public instance should be pointed by the vhost A records."
  default = "proxy"
}

variable "public_instances" { }

variable "ssh_private_key" {
  type = string
}