# MetalLB Test

- create nginx deployment + loadbalancer service
// kubectl create deployment nginx --image=nginx
// kubectl create deployment nginx --type=LoadBalancer --port=80 --target-port=80
// kubectl get svc nginx -o wide

- got the EXTERNAL-IP from the pool
- curl to EXTERNAL-IP
curl -I http://<EXTERNAL-IP>

if curl returns 200, everything is working just fine.
