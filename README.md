# hetzner-unikernels

Unikernel examples and tooling for Hetzner Cloud using [NanoVMs OPS](https://ops.city/).

## Examples

### hello-http

A minimal Go HTTP server that responds with a greeting. Intended as a starting point for deploying unikernels to Hetzner Cloud.

```
examples/
└── hello-http/
    └── main.go
```

#### Build & Run locally

```bash
cd examples/hello-http
ops run main.go
```

#### Deploy to Hetzner

Set the required environment variables:

```bash
export HCLOUD_TOKEN=<your-hetzner-api-token>
export OBJECT_STORAGE_DOMAIN=hel1.your-objectstorage.com
export OBJECT_STORAGE_KEY=<your-access-key>
export OBJECT_STORAGE_SECRET=<your-secret-key>
```

Create and deploy the image:

```bash
ops image create -t hetzner -c config.json examples/hello-http/main.go
ops instance create -t hetzner -c config.json main -p 8080
```

See the [OPS Hetzner docs](https://github.com/nanovms/ops-documentation/blob/master/hetzner.md) for full details.
