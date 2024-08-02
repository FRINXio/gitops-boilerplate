# gitops-boilerplate

This repository provides instructions for installing and managing Frinx Machine on Kubernetes.

Part of installation is also deploying custom worker from [frinx-workers-boilerplate](https://github.com/FRINXio/frinx-workers-boilerplate).

Follow the instructions below to get started.

### Prerequisities

Before you begin, ensure you have the following tools installed:

- [`docker`](https://docs.docker.com/engine/install/)
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/)
- [`minikube`](https://minikube.sigs.k8s.io/docs/start/)
- [`helm`](https://helm.sh/docs/intro/install/)
- [`just`](https://github.com/casey/just)


## Quick Start

### Docker login

Justfile uses `~/.docker/config.json` path for creating kubernetes docker registry secret.
For accessing private images, please contact `marketing@elisapolystar.com`

### Local ingress configuration

In case, you using minikube, get minikube ip

```bash
minikube ip

192.168.49.2
```

add map that ip with ingres hosts to your /etc/hosts

```bash
#/etc/hosts
192.168.49.2 krakend.127.0.0.1.nip.io
192.168.49.2 workflow-manager.127.0.0.1.nip.io
```

### Install Frinx Machine locally

Frinx Machine is deployed to the `gitops-boilerplate` namespace.
The `justfile` provides commands to manage the local deployment process easily.

> [!NOTE]  
> justfile uses local-values.yaml by default
> to override it, use just --set values "" deploy

```bash
just # print help

# start Minikube with required parameters
just minikube-start

# deploy FM with specific

just deploy

# exclude apps from deployment
just --set exclude "custom-worker" deploy 

# include custom values
just --set values "local-values.yaml" deploy 
just --set values "cluster-values.yaml" deploy 

# uninstall deployment with specific stage
just uninstall
```

### Advanced deployment configuration

For detailed documentation and advanced configuration options, 
please refer to the individual Chart.yaml and values.yaml files located in the apps directory.

More more info visit [Frinx Helm Charts](https://artifacthub.io/packages/search?org=frinx)
