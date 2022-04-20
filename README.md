cloudflare-update
===============

Introduction
------------

A script for dynamically updating a CloudFlare DNS record.  I use CloudFlare
to host DNS for a domain and I wanted to point an A record in that domain to
a host whose IP address changes occasionally.  CloudFlare has an API to do this,
so this project was created.

Configuration
-------------

This project uses Docker. You can use the `run.sh` script, as specified, to run
the project. It will build the image for the project, and will start a container
based on the image.

Before running the `run.sh` script, make sure to create a `config` folder.

The `config` folder should contain a `config.ini` file, with the following format:

```
healthcheck_url="https://hc-ping.com/ffffffff-ffff-ffff-ffff-ffffffffffff"
api_token="fffffffffffffffffffffffff-fffffff-ffffff"
skip_records="skip1.example.com skip2.example.com"
zones="example.com"
```

The `healthcheck_url` option is not required. It is only necessary if you would
like the service to send a health check heartbeat to a specified URL after running.

The `api_token` option should contain your CloudFlare v4 API token.

The `skip_records` option can contain a list of subdomains to skip updating.

The `zones` option should contain a list of CloudFlare domains to update.
All subdomains that are not in the `skip_records` list will be updated with
bpth the server's IPv4 and IPv6 address, provided that the respective A and
AAAA records exist.
