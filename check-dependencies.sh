#!/bin/bash

# check-dependencies.sh for infra-cluster-kind
# Verifies all required dependencies are installed before cluster setup

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Dependency Check for Infrastructure Setup ===${NC}"
echo ""

# Track overall status
ALL_GOOD=true

# Check Docker
echo -n "Checking Docker... "
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
    echo -e "${GREEN}✓${NC} (${DOCKER_VERSION})"

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        echo -e "  ${YELLOW}⚠${NC}  Docker daemon is not running. Start it with: sudo systemctl start docker"
        ALL_GOOD=false
    fi

    # Check if user is in docker group
    if ! groups | grep -q docker; then
        echo -e "  ${YELLOW}⚠${NC}  User not in 'docker' group. Add with: sudo usermod -aG docker \$USER"
        echo -e "      Then log out and back in for changes to take effect."
    fi
else
    echo -e "${RED}✗ NOT FOUND${NC}"
    echo -e "  Install: https://docs.docker.com/get-docker/"
    ALL_GOOD=false
fi

# Check kubectl
echo -n "Checking kubectl... "
if command -v kubectl &> /dev/null; then
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null | awk '{print $3}')
    echo -e "${GREEN}✓${NC} (${KUBECTL_VERSION})"
else
    echo -e "${RED}✗ NOT FOUND${NC}"
    echo -e "  Install: https://kubernetes.io/docs/tasks/tools/"
    ALL_GOOD=false
fi

# Check kind
echo -n "Checking kind... "
if command -v kind &> /dev/null; then
    KIND_VERSION=$(kind version | awk '{print $2}')
    echo -e "${GREEN}✓${NC} (${KIND_VERSION})"
else
    echo -e "${RED}✗ NOT FOUND${NC}"
    echo -e "  Install: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    ALL_GOOD=false
fi

# Check curl (needed by install script)
echo -n "Checking curl... "
if command -v curl &> /dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ NOT FOUND${NC}"
    echo -e "  Install: sudo apt-get install curl (Debian/Ubuntu)"
    ALL_GOOD=false
fi

echo ""
echo -e "${GREEN}=== System Configuration Checks ===${NC}"
echo ""

# Check inotify limits (CRITICAL for Kind clusters)
echo "Checking inotify limits (CRITICAL for cluster stability):"
INOTIFY_WATCHES=$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo "0")
INOTIFY_INSTANCES=$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo "0")

echo -n "  fs.inotify.max_user_watches... "
if [ "$INOTIFY_WATCHES" -ge 524288 ]; then
    echo -e "${GREEN}✓${NC} (${INOTIFY_WATCHES})"
else
    echo -e "${RED}✗ TOO LOW${NC} (${INOTIFY_WATCHES}, recommended: 524288)"
    echo -e "    ${YELLOW}This WILL cause cluster failures after ~45 hours!${NC}"
    echo -e "    Fix with:"
    echo -e "      sudo sysctl -w fs.inotify.max_user_watches=524288"
    echo -e "      echo 'fs.inotify.max_user_watches = 524288' | sudo tee -a /etc/sysctl.conf"
    ALL_GOOD=false
fi

echo -n "  fs.inotify.max_user_instances... "
if [ "$INOTIFY_INSTANCES" -ge 512 ]; then
    echo -e "${GREEN}✓${NC} (${INOTIFY_INSTANCES})"
else
    echo -e "${RED}✗ TOO LOW${NC} (${INOTIFY_INSTANCES}, recommended: 512)"
    echo -e "    Fix with:"
    echo -e "      sudo sysctl -w fs.inotify.max_user_instances=512"
    echo -e "      echo 'fs.inotify.max_user_instances = 512' | sudo tee -a /etc/sysctl.conf"
    ALL_GOOD=false
fi

echo ""
echo -e "${GREEN}=== Summary ===${NC}"
echo ""

if [ "$ALL_GOOD" = true ]; then
    echo -e "${GREEN}✓ All dependencies satisfied!${NC}"
    echo -e "Ready to run: ./install.sh"
    exit 0
else
    echo -e "${RED}✗ Some dependencies are missing or misconfigured.${NC}"
    echo -e "Please install/configure missing items and run this check again."
    exit 1
fi
