#!/bin/bash

# infra-cluster-kind installation script
# Creates Kind cluster and installs MetalLB for LoadBalancer services

set -e  # Exit on any error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="sre-lab"
METALLB_VERSION="v0.14.5"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}=== SRE Lab Infrastructure Setup ===${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: docker not found. Please install Docker first.${NC}"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

if ! command -v kind &> /dev/null; then
    echo -e "${RED}Error: kind not found. Please install kind first.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites found${NC}"
echo ""

# Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${YELLOW}Warning: Cluster '${CLUSTER_NAME}' already exists.${NC}"
    read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deleting existing cluster...${NC}"
        kind delete cluster --name "${CLUSTER_NAME}"
    else
        echo -e "${YELLOW}Skipping cluster creation. Will attempt to configure MetalLB.${NC}"
        SKIP_CLUSTER_CREATE=true
    fi
fi

# Create Kind cluster
if [ "$SKIP_CLUSTER_CREATE" != "true" ]; then
    echo -e "${GREEN}Creating Kind cluster '${CLUSTER_NAME}'...${NC}"
    kind create cluster --config "${SCRIPT_DIR}/cluster/kind-cluster-3w.yaml"
    echo -e "${GREEN}✓ Cluster created successfully${NC}"
    echo ""

    # Wait for cluster to be ready
    echo -e "${YELLOW}Waiting for cluster to be ready...${NC}"
    kubectl wait --for=condition=Ready nodes --all --timeout=120s
    echo -e "${GREEN}✓ Cluster is ready${NC}"
    echo ""
fi

# Display cluster info
echo -e "${GREEN}Cluster information:${NC}"
kubectl cluster-info
echo ""
kubectl get nodes -o wide
echo ""

# Install MetalLB
echo -e "${GREEN}Installing MetalLB ${METALLB_VERSION}...${NC}"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml

echo -e "${YELLOW}Waiting for MetalLB pods to be ready...${NC}"
kubectl wait --namespace metallb-system \
    --for=condition=ready pod \
    --selector=app=metallb \
    --timeout=120s

echo -e "${GREEN}✓ MetalLB installed successfully${NC}"
echo ""

# Apply MetalLB configuration
echo -e "${GREEN}Applying MetalLB configuration...${NC}"
kubectl apply -f "${SCRIPT_DIR}/metallb/ipaddresspool.yaml"
kubectl apply -f "${SCRIPT_DIR}/metallb/l2advertisement.yaml"

echo -e "${GREEN}✓ MetalLB configured successfully${NC}"
echo ""

# Verify MetalLB installation
echo -e "${GREEN}Verifying MetalLB installation:${NC}"
echo ""
echo "MetalLB Pods:"
kubectl get pods -n metallb-system
echo ""
echo "IP Address Pool:"
kubectl get ipaddresspool -n metallb-system
echo ""
echo "L2 Advertisement:"
kubectl get l2advertisement -n metallb-system
echo ""

# Inspect Kind network
echo -e "${GREEN}Kind network details:${NC}"
docker network inspect kind | grep -E "Subnet|Gateway" || true
echo ""

# Offer to run smoke test
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Run smoke test: kubectl create deployment nginx --image=nginx && kubectl expose deployment nginx --type=LoadBalancer --port=80"
echo "2. Check LoadBalancer IP: kubectl get svc nginx"
echo "3. Test connectivity: curl -I http://<EXTERNAL-IP>"
echo "4. Cleanup test: kubectl delete svc nginx && kubectl delete deployment nginx"
echo ""
echo "Or proceed to deploy the observability stack from ../observability-stack"
echo ""

read -p "Do you want to run the smoke test now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Running smoke test...${NC}"

    # Create nginx deployment and service
    kubectl create deployment nginx --image=nginx
    kubectl expose deployment nginx --type=LoadBalancer --port=80

    echo -e "${YELLOW}Waiting for LoadBalancer IP to be assigned...${NC}"
    for i in {1..30}; do
        EXTERNAL_IP=$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [ -n "$EXTERNAL_IP" ]; then
            echo -e "${GREEN}✓ LoadBalancer IP assigned: ${EXTERNAL_IP}${NC}"
            break
        fi
        sleep 2
        echo -n "."
    done
    echo ""

    if [ -n "$EXTERNAL_IP" ]; then
        echo -e "${GREEN}Testing connectivity to nginx...${NC}"
        sleep 5  # Give nginx a moment to start
        if curl -I -s --max-time 10 "http://${EXTERNAL_IP}" | head -n 1 | grep -q "200 OK"; then
            echo -e "${GREEN}✓ Smoke test PASSED! MetalLB is working correctly.${NC}"
        else
            echo -e "${RED}✗ Smoke test FAILED. Could not reach nginx.${NC}"
        fi

        read -p "Do you want to cleanup the smoke test resources? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            kubectl delete svc nginx
            kubectl delete deployment nginx
            echo -e "${GREEN}✓ Smoke test resources cleaned up${NC}"
        fi
    else
        echo -e "${RED}✗ Failed to get LoadBalancer IP. Check MetalLB logs.${NC}"
    fi
fi

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
