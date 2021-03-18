variable "config_git_url" {
  type        = string
  description = "URL to the Magic Castle Puppet configuration git repo"
}

variable "config_version" {
  type        = string
  description = "Tag, branch, or commit that specifies which Puppet configuration revision is to be used"
}

variable "domain" {}

variable "image" {}

variable "sudoer_username" { default = "" }

variable "nb_users" {}

variable "guest_passwd" {}

variable "cluster_name" {}

variable "root_disk_size" {
  default = 20
}

variable "instances" {
  description = "Map that defines the parameters for each type of instance of the cluster"
  default     = {}
}

variable "storage" {
  default = {}
}

variable "firewall_rules" {
  type = list(
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
      "name"        = "SSH",
      "from_port"   = 22,
      "to_port"     = 22,
      "ip_protocol" = "tcp",
      "cidr"        = "0.0.0.0/0"
    },
    {
      "name"        = "HTTP",
      "from_port"   = 80,
      "to_port"     = 80,
      "ip_protocol" = "tcp",
      "cidr"        = "0.0.0.0/0"
    },
    {
      "name"        = "HTTPS",
      "from_port"   = 443,
      "to_port"     = 443,
      "ip_protocol" = "tcp",
      "cidr"        = "0.0.0.0/0"
    },
    {
      "name"        = "Globus",
      "from_port"   = 2811,
      "to_port"     = 2811,
      "ip_protocol" = "tcp",
      "cidr"        = "54.237.254.192/29"
    },
    {
      "name"        = "MyProxy",
      "from_port"   = 7512,
      "to_port"     = 7512,
      "ip_protocol" = "tcp",
      "cidr"        = "0.0.0.0/0"
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

variable "public_keys" {
  default = []
}