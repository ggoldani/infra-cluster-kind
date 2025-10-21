# Host setup (Debian)

## Tools & versions
- Docker: Docker version 28.5.1, build e180ab8
- kubectl: Client Version: v1.31.0
- kind: kind version 0.23.0
- Helm: v3.19.0+g3d8990f
- k6: k6 v1.3.0 (commit/5870e99ae8, go1.25.1, linux/amd64)
- Python: Python 3.13.5
- Git: git version 2.47.3

## Notes
- User added to docker group for rootless usage.
- This lab targets Kind + MetalLB + Grafana stack + OTEL Collector.
