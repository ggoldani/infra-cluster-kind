# infra-cluster-kind

Kubernetes infrastructure layer using Kind (Kubernetes in Docker) with MetalLB for LoadBalancer support.

---

## Purpose

Creates a local Kubernetes cluster that simulates a cloud environment by providing **LoadBalancer services with real external IPs** - essential for the observability stack's architecture.

**Why MetalLB?** In cloud environments (GKE, EKS, AKS), LoadBalancer services automatically get external IPs. Kind doesn't have this by default. MetalLB fills this gap for local development/learning.

---

## What's Included

```
infra-cluster-kind/
├── install.sh                    # Automated installation script
├── check-dependencies.sh         # Verify prerequisites
├── cluster/
│   └── kind-cluster-3w.yaml     # Kind cluster configuration (1 control-plane + 3 workers)
├── metallb/
│   ├── ipaddresspool.yaml       # IP range: 172.18.255.200-250
│   └── l2advertisement.yaml     # Layer 2 advertisement config
└── docs/                         # Additional documentation
```

---

## Prerequisites

Before running the installation:

### Required Tools

- **Docker** 28.5.1+ (container runtime)
- **kubectl** 1.31.0+ (Kubernetes CLI)
- **kind** 0.23.0+ (Kubernetes in Docker)
- **jq** (JSON processor, used by scripts)

### Verify Prerequisites

```bash
./check-dependencies.sh
```

### Critical System Configuration

⚠️ **REQUIRED:** Set inotify limits BEFORE creating the cluster:

```bash
sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=512
echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf
echo "fs.inotify.max_user_instances = 512" | sudo tee -a /etc/sysctl.conf
```

**Why this matters:** Default Debian inotify limits (64k watches) cause cluster-wide DNS failures after ~45 hours. Docker + Kind + multiple pods exhaust this limit. See `../SRE-laboratory/docs/runbooks/cluster-dns-failure-inotify-exhaustion.md` for technical details.

**Verify settings:**
```bash
sysctl fs.inotify.max_user_watches   # Should show 524288
sysctl fs.inotify.max_user_instances # Should show 512
```

---

## Installation

### Automated Installation (Recommended)

```bash
./install.sh
```

**What it does:**
1. Checks prerequisites (docker, kubectl, kind)
2. Creates Kind cluster with 1 control-plane + 3 workers
3. Installs MetalLB (v0.14.5)
4. Configures IP address pool (172.18.255.200-250)
5. Runs optional smoke test

**Script behavior:**
- **Idempotent**: Safe to re-run
- **Interactive**: Prompts before deleting existing cluster
- **Self-documenting**: Shows next steps after completion

**Installation time:** ~3-5 minutes

### Manual Installation

If you prefer step-by-step control:

```bash
# 1. Create cluster
kind create cluster --config cluster/kind-cluster-3w.yaml --name sre-lab

# 2. Wait for cluster to be ready
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# 3. Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

# 4. Wait for MetalLB pods
kubectl wait --namespace metallb-system \
    --for=condition=ready pod \
    --selector=app=metallb \
    --timeout=120s

# 5. Configure MetalLB
kubectl apply -f metallb/ipaddresspool.yaml
kubectl apply -f metallb/l2advertisement.yaml
```

---

## Verification

### Check Cluster Health

```bash
# Cluster info
kubectl cluster-info --context kind-sre-lab

# Node status (should show 4 nodes: 1 control-plane + 3 workers)
kubectl get nodes -o wide

# MetalLB pods (should all be Running)
kubectl get pods -n metallb-system

# MetalLB configuration
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

### Smoke Test

Test that LoadBalancer IPs are actually assigned:

```bash
# Create test nginx service
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --type=LoadBalancer --port=80

# Wait for IP assignment (takes 5-10 seconds)
kubectl get svc nginx -w

# Test connectivity
EXTERNAL_IP=$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -I http://${EXTERNAL_IP}

# Cleanup
kubectl delete svc nginx
kubectl delete deployment nginx
```

---

## Network Configuration

### Kind Network

Kind creates a Docker bridge network:
- **Network:** `172.18.0.0/16`
- **Gateway:** `172.18.0.1`
- **Node IPs:** Assigned from this range

```bash
# Inspect Kind network
docker network inspect kind | grep -E "Subnet|Gateway"
```

### MetalLB IP Pool

Configured in `metallb/ipaddresspool.yaml`:
- **Range:** `172.18.255.200 - 172.18.255.250`
- **Available IPs:** 51 addresses
- **Mode:** Layer 2 (ARP)

**Why this range?** It's within the Kind network (`172.18.0.0/16`) but at the high end to avoid conflicts with node IPs.

### LoadBalancer Assignment

When you create a `type: LoadBalancer` service:
1. Kubernetes creates the service
2. MetalLB controller sees the request
3. MetalLB assigns an IP from the pool
4. MetalLB speaker announces the IP via ARP (Layer 2)
5. Host machine can reach the service at `http://<EXTERNAL-IP>`

---

## Cluster Configuration

Defined in `cluster/kind-cluster-3w.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: sre-lab
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
```

**Design choices:**
- **1 control-plane:** Single point of control (not HA, but sufficient for learning)
- **3 workers:** Allows testing distributed workloads, replica placement, etc.
- **No ingress:** Using LoadBalancer services instead (simpler for observability endpoints)

---

## Common Operations

### Delete Cluster

```bash
kind delete cluster --name sre-lab
```

### Recreate Cluster

```bash
kind delete cluster --name sre-lab
./install.sh
```

### Context Switching

If using multiple clusters:

```bash
# Switch to this cluster
kubectl config use-context kind-sre-lab

# View current context
kubectl config current-context

# List all contexts
kubectl config get-contexts
```

### Check Docker Resources

```bash
# View Kind containers
docker ps | grep sre-lab

# Check Kind container resource usage
docker stats $(docker ps --filter "name=sre-lab" -q)
```

---

## Troubleshooting

### Cluster Creation Fails

**Symptom:** `kind create cluster` hangs or fails

**Common causes:**
1. Docker not running: `sudo systemctl start docker`
2. Insufficient Docker resources (needs ~4GB RAM)
3. Port conflicts (6443 already in use)

**Solution:**
```bash
# Check Docker
docker ps

# Remove conflicting clusters
kind delete cluster --name sre-lab

# Try again
./install.sh
```

### MetalLB IPs Not Assigned

**Symptom:** Services stuck with `<pending>` external IP

**Diagnosis:**
```bash
# Check MetalLB pods
kubectl get pods -n metallb-system

# Check MetalLB logs
kubectl logs -n metallb-system -l app=metallb

# Verify IP pool exists
kubectl get ipaddresspool -n metallb-system -o yaml
```

**Common causes:**
1. MetalLB pods not running
2. IP pool not applied
3. Network misconfiguration

**Solution:**
```bash
# Reapply MetalLB configuration
kubectl apply -f metallb/ipaddresspool.yaml
kubectl apply -f metallb/l2advertisement.yaml
```

### DNS Resolution Failures

**Symptom:** CoreDNS pods not ready, DNS not working

**Likely cause:** Inotify exhaustion (if cluster has been running 45+ hours)

**Diagnosis:**
```bash
# Check CoreDNS status
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check inotify usage
for foo in /proc/*/fd/*; do readlink -f $foo; done | grep inotify | wc -l
```

**Solution:** See `../SRE-laboratory/docs/runbooks/cluster-dns-failure-inotify-exhaustion.md`

---

## Next Steps

After successful installation:

1. **Deploy observability stack:**
   ```bash
   cd ../observability-stack
   ./install.sh
   ```

2. **Verify LoadBalancers work:**
   All observability services will request LoadBalancer IPs from MetalLB

3. **Learn more:**
   - [Kind documentation](https://kind.sigs.k8s.io/)
   - [MetalLB concepts](https://metallb.universe.tf/concepts/)
   - [Kubernetes services](https://kubernetes.io/docs/concepts/services-networking/service/)

---

## Technical Details

### Why Kind?

**Pros:**
- Fast cluster creation (~60 seconds)
- Full Kubernetes feature set (unlike minikube)
- Multiple nodes (simulates real clusters)
- Clean isolation (each cluster is Docker containers)

**Cons:**
- No LoadBalancer by default (solved with MetalLB)
- Not suitable for production (by design)

### Why MetalLB?

**Alternatives considered:**
- **Port forwarding:** Doesn't simulate real LoadBalancers, requires manual port management
- **NodePort:** Requires remembering high ports (30000+), not production-like
- **Ingress:** Overkill for observability endpoints, adds complexity

**MetalLB advantages:**
- Production-like behavior (services get real IPs)
- Simple Layer 2 mode (no BGP needed)
- Automatic IP assignment
- Works with standard Kubernetes manifests

---

## Storage

This component doesn't provision persistent storage. Storage is handled by:
- **Kind's default:** Uses local-path provisioner (hostPath on nodes)
- **Observability stack:** Creates PVCs that use Kind's default storage class

---

**Part of:** [SRE Lab](../README.md)
**Next Component:** [observability-stack](../observability-stack/README.md)
