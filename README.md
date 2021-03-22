# Magic Castle 20 (_experimental_)

Experimental repo trying to modernize
[Magic Castle](https://www.github.com/ComputeCanada/magic_castle)
instances interface to accomodate more than just
`mgmt`, `login` and `node`.

This repo is currently only compatible with OpenStack.

Example:
```
  instances = {
    puppet   = { type = "p4-6gb", tags = ["puppet"] }
    mgmt     = { type = "p4-6gb", tags = ["mgmt", "nfs"] },
    login    = { type = "p2-3gb", tags = ["login", "proxy", "public"] },
    node     = { type = "p2-3gb", tags = ["node"], count = 2 },
    gpu      = { type = "g1-18gb-c4-22gb", tags = ["node"], count = 2  },
  }

  storage = {
    nfs = {
      home     = 50
      project  = 100
      scratch  = 100
      misc     = 10
    }
  }
```

## Tags meaning

- `puppet`: Designate the instance that will act as the puppet-server.
- `public`: Designate instances that needs to have a public ip address.
- `nfs`: Designate the instance to which will be attached the `nfs` volumes
defined in `storage`.
- `proxy`: When combined with `public`, it designates the instances that will be pointed by the vhost A records. It also designate a host that will receive a copy of the SSL wildcard certificate.
- `login`: When combined with `public`, it designates the instances that will be pointed by the `${cluster_name}.${domain}` A records.
- `ssl`: When combined with `public`, it designated an instance that will receive a copy of the wildcard certificate.


Unused tags for now:
- `mgmt`
- `node`

## what is missing?

- Replacing hostnames by tags to identify instance role in the cluster
