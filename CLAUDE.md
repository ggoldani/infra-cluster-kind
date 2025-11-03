# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Infrastructure component for the SRE lab that provides a local Kubernetes cluster with LoadBalancer capabilities using Kind and MetalLB. This simulates a cloud-like environment locally by providing EXTERNAL-IP addresses for LoadBalancer services.

## Architecture

### Kind Cluster Configuration
- **Cluster name**: sre-lab
- **Nodes**: 1 control-plane + 3 worker nodes
- **Network**: Docker network 172.18.0.0/16 (automatically created by Kind)
- **Port mapping**: Control plane port 30000 exposed to host (for NodePort testing)
- **Config file**: `cluster/kind-cluster-3w.yaml`

### MetalLB LoadBalancer
- **Version**: v0.14.5
- **Mode**: Layer2
- **IP pool**: 172.18.255.200-172.18.255.250 (51 addresses)
- **Purpose**: Allocate EXTERNAL-IP addresses to LoadBalancer-type services
- **Resources**:
  - `metallb/ipaddresspool.yaml` - Defines the IP address range
  - `metallb/l2advertisement.yaml` - Configures layer2 advertisement
  - `metallb/metallb-config.yaml` - Legacy ConfigMap (not actively used)

## Quick Start

The easiest way to set up the infrastructure is to use the automated installation script:

```bash
# Run the installation script
./install.sh
```

This script will:
- Check prerequisites (Docker, kubectl, kind)
- Create the Kind cluster
- Install and configure MetalLB
- Verify the installation
- Optionally run a smoke test

## Common Commands

### Cluster Lifecycle

```bash
# Create cluster
kind create cluster --config cluster/kind-cluster-3w.yaml

# Validate cluster
kubectl cluster-info
kubectl get nodes -o wide

# Delete cluster (cleanup)
kind delete cluster --name sre-lab
```

### MetalLB Installation

```bash
# Install MetalLB (run after cluster creation)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# Wait for MetalLB pods to be ready
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s

# Apply IP pool configuration
kubectl apply -f metallb/ipaddresspool.yaml
kubectl apply -f metallb/l2advertisement.yaml

# Verify MetalLB installation
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

### Verification & Testing

```bash
# Smoke test - Create nginx LoadBalancer service
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --type=LoadBalancer --port=80
kubectl get svc nginx -o wide  # Wait for EXTERNAL-IP to be assigned

# Test LoadBalancer connectivity
NGINX_IP=$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -I http://$NGINX_IP  # Should return HTTP 200 OK

# Cleanup smoke test
kubectl delete svc nginx
kubectl delete deployment nginx

# Inspect Kind network details
docker network inspect kind | grep Subnet
docker network inspect kind | grep Gateway
```

### Debugging

```bash
# Check MetalLB pods
kubectl get pods -n metallb-system
kubectl logs -n metallb-system -l component=controller
kubectl logs -n metallb-system -l component=speaker

# Verify IP pool configuration
kubectl describe ipaddresspool -n metallb-system default-pool

# Check L2 advertisement
kubectl describe l2advertisement -n metallb-system default-l2adv

# List all LoadBalancer services across namespaces
kubectl get svc --all-namespaces -o wide | grep LoadBalancer

# Check Kind node details
kubectl get nodes -o wide
docker ps | grep sre-lab
```

## Important Notes

### Network Architecture
- Kind creates a dedicated Docker network with subnet 172.18.0.0/16
- MetalLB IP pool (172.18.255.200-250) must be within this subnet
- The control plane node has port 30000 mapped to the host for NodePort service testing
- LoadBalancer IPs are only accessible from the Docker host, not from outside the host

### Configuration Conventions
- All YAML manifests use declarative configuration
- MetalLB resources target the `metallb-system` namespace
- IP pool name: `default-pool` (referenced by L2Advertisement)
- L2 advertisement name: `default-l2adv`

### Host Requirements
- Docker installed and running (version 28.5.1 or later recommended)
- kubectl installed (version 1.31.0 or later recommended)
- kind installed (version 0.23.0 or later recommended)
- User must be in the `docker` group for rootless container usage
- Sufficient resources: ~4 CPU cores, 8GB RAM recommended for 3-worker cluster

### Common Issues

**MetalLB pods not starting:**
- Wait 1-2 minutes after cluster creation before installing MetalLB
- Check: `kubectl get pods -n metallb-system -w`

**LoadBalancer stuck in Pending:**
- Verify MetalLB is running: `kubectl get pods -n metallb-system`
- Verify IP pool is configured: `kubectl get ipaddresspool -n metallb-system`
- Check speaker logs: `kubectl logs -n metallb-system -l component=speaker`

**EXTERNAL-IP not accessible:**
- Verify IP is within the Kind network subnet
- Check from Docker host: `docker network inspect kind`
- LoadBalancer IPs are only accessible from the Docker host machine

### Integration with Observability Stack
This infrastructure component is designed to work with the `observability-stack` repository:
- Observability components (Grafana, Mimir, Loki, Tempo) run as LoadBalancer services
- MetalLB allocates IPs from the pool to make these services accessible
- The cluster provides the compute platform; this repo provides the networking layer
- Cluster must be created and MetalLB installed before deploying observability components
