# Kind Network Details

To find out the kind subnet:
docker network inspect kind | grep Subnet

- subnet: 172.18.0.0/16
- metalLB pool: 172.18.255.200-172.18.255.250
- purpose: allocate EXTERNAL-IP for LoadBalancer Services
