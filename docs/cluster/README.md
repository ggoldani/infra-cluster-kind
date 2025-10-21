# Kind Cluster - sre-lab

## Create
kind create cluster --config cluster/kind-config.yaml

## Validate
kubectl cluster-info
kubectl get nodes -o wide

## Delete (cleanup)
kind delete cluster --name sre-lab
