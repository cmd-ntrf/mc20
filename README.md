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
    mgmt     = { type = "p4-6gb", tags = ["mgmt", "storage"] },
    login    = { type = "p2-3gb", tags = ["login", "proxy", "public"] },
    node     = { type = "p2-3gb", tags = ["node"], count = 2 },
    gpu      = { type = "g1-18gb-c4-22gb", tags = ["node"], count = 2  },
  }
```

## what is missing?

- DNS records
- Login SSH Hostkeys
- Replacing hostnames by tags to identify instance role in the cluster
