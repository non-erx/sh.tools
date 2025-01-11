#!/bin/bash

# Enable strict error handling
set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

# Script variables
readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
readonly PHONERX_USER="phonerx"
readonly PHONERX_PASS="phonerx"
readonly DOCKER_NETWORK="ptools-erx"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Error handling
msg() {
    echo >&2 -e "${1-}"
}

die() {
    local msg=$1
    local code=${2-1}
    msg "${RED}[✗] ${msg}${NC}"
    exit "$code"
}

setup_colors() {
    if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
        NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' BLUE='\033[0;34m'
    else
        NOFORMAT='' RED='' GREEN='' BLUE=''
    fi
}

# ASCII Art Welcome Banner
show_welcome() {
    echo '
    ██████╗ ██╗  ██╗ ██████╗ ███╗   ██╗███████╗   ███████╗██████╗ ██╗  ██╗
    ██╔══██╗██║  ██║██╔═══██╗████╗  ██║██╔════╝   ██╔════╝██╔══██╗╚██╗██╔╝
    ██████╔╝███████║██║   ██║██╔██╗ ██║█████╗     █████╗  ██████╔╝ ╚███╔╝ 
    ██╔═══╝ ██╔══██║██║   ██║██║╚██╗██║██╔══╝     ██╔══╝  ██╔══██╗ ██╔██╗ 
    ██║     ██║  ██║╚██████╔╝██║ ╚████║███████╗   ███████╗██║  ██║██╔╝ ██╗
    ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝
                                                                by @non-erx
    '
    echo -e "${BLUE}Pentest Toolset Installation Script${NC}"
    echo "-----------------------------------"
}

# Check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "\nThis script requires root privileges for:"
        echo "- Installing system packages and dependencies"
        echo "- Creating new user accounts"
        echo "- Configuring Docker and network settings"
        echo "- Setting up firewall rules"
        echo "- Managing system services"
        echo "- Modifying system configurations"
        
        echo -n "Would you like to run this script with sudo? (Y/N): "
        read -r response
        case "$response" in 
            [Yy]* )
                exec sudo bash "$0" "$@"
                ;;
            * )
                die "Root privileges required. Exiting..."
                ;;
        esac
    fi
}

# Create phonerx user with sudo privileges
create_user() {
    msg "${GREEN}[+] Creating ${PHONERX_USER} user...${NC}"
    if id "$PHONERX_USER" &>/dev/null; then
        msg "${BLUE}[i] User ${PHONERX_USER} already exists${NC}"
    else
        useradd -m -s /bin/bash "$PHONERX_USER"
        echo "${PHONERX_USER}:${PHONERX_PASS}" | chpasswd
        usermod -aG sudo "$PHONERX_USER"
        usermod -aG docker "$PHONERX_USER"
    fi
}

# Detect OS
detect_os() {
    if [ -f /etc/arch-release ]; then
        echo "arch"
    elif [ -f /etc/lsb-release ]; then
        echo "ubuntu"
    else
        die "Unsupported operating system"
    fi
}

# Install prerequisites
install_prerequisites() {
    local os=$1
    msg "${GREEN}[+] Installing prerequisites...${NC}"
    if [ "$os" == "ubuntu" ]; then
        apt update
        apt install -y curl wget git python3-pip software-properties-common apt-transport-https snapd
    elif [ "$os" == "arch" ]; then
        pacman -Syu --noconfirm
        pacman -S --noconfirm curl wget git python-pip snapd
    fi
}

# Update system based on OS
update_system() {
    local os=$1
    msg "${GREEN}[+] Updating system...${NC}"
    if [ "$os" == "arch" ]; then
        pacman -Syu --noconfirm
        systemctl enable --now snapd.socket
        systemctl start snapd.service
        ln -sf /var/lib/snapd/snap /snap
    elif [ "$os" == "ubuntu" ]; then
        apt update && apt upgrade -y
        systemctl enable --now snapd.socket
        systemctl start snapd.service
    fi
    
    msg "${BLUE}[i] Waiting for snap service to initialize...${NC}"
    sleep 10
    snap wait system seed.loaded
}

# Install system applications
install_system_apps() {
    local os=$1
    msg "${GREEN}[+] Installing system applications...${NC}"
    
    if [ "$os" == "arch" ]; then
        # Install yay
        if ! command -v yay &>/dev/null; then
            git clone https://aur.archlinux.org/yay.git
            cd yay || die "Failed to enter yay directory"
            makepkg -si --noconfirm
            cd .. && rm -rf yay
        fi
        
        # Install packages
        pacman -S --noconfirm code gcc android-studio
        yay -S --noconfirm tabby-bin zen-browser
        
    elif [ "$os" == "ubuntu" ]; then
        # VSCode
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/vscode stable main" | tee /etc/apt/sources.list.d/vscode.list
        apt update && apt install -y code g++
        
        # Android Studio
        add-apt-repository ppa:maarten-fonville/android-studio -y
        apt update && apt install -y android-studio
        
        # Tabby
        wget "https://github.com/Eugeny/tabby/releases/latest/download/tabby-1.0.0-linux-x64.deb"
        dpkg -i tabby-1.0.0-linux-x64.deb || apt install -f -y
        rm tabby-1.0.0-linux-x64.deb
        
        # Zen Browser
        snap install zen-browser
    fi
}

# Configure Android Studio
configure_android_studio() {
    msg "${GREEN}[+] Configuring Android Studio...${NC}"
    local config_dir="/home/${PHONERX_USER}/.AndroidStudio"
    mkdir -p "$config_dir"
    cat > "${config_dir}/docker.properties" << EOF
docker.network=${DOCKER_NETWORK}
docker.socket=/var/run/docker.sock
EOF
    chown -R "${PHONERX_USER}:${PHONERX_USER}" "$config_dir"
}

# Install and configure firewall
setup_firewall() {
    msg "${GREEN}[+] Setting up UFW firewall...${NC}"
    apt install -y ufw
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 8080/tcp  # Caido
    ufw allow 9000/tcp  # Portainer
    ufw allow 5037/tcp  # ADB
    ufw allow 8000/tcp  # MobSF
    ufw allow 5000/tcp  # RMS
    ufw allow 8070/tcp  # JADX
    ufw allow 3000/tcp  # Grapefruit
    echo "y" | ufw enable
}

# Install Docker
install_docker() {
    local os=$1
    msg "${GREEN}[+] Installing Docker...${NC}"
    if [ "$os" == "arch" ]; then
        pacman -S --noconfirm docker docker-compose
    elif [ "$os" == "ubuntu" ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt update
        apt install -y docker-ce docker-ce-cli containerd.io docker-compose
    fi
    
    systemctl enable docker
    systemctl start docker
    
    # Create pentest network
    docker network create "$DOCKER_NETWORK" || true
}

# Setup Docker containers
setup_docker_containers() {
    msg "${GREEN}[+] Setting up Docker containers...${NC}"
    
    # Create shared volume
    docker volume create pentest_data

    # Array of container configurations
    declare -A containers
    
    # Portainer
    docker run -d \
        --name portainer \
        --network "$DOCKER_NETWORK" \
        --restart always \
        -p 9000:9000 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce

    # SQLMap
    docker run -d \
        --name sqlmap \
        --network "$DOCKER_NETWORK" \
        -v pentest_data:/root/.sqlmap \
        ahacking/sqlmap
    
    # Nmap
    docker run -d \
        --name nmap \
        --network "$DOCKER_NETWORK" \
        --cap-add=NET_ADMIN \
        --cap-add=NET_RAW \
        instrumentisto/nmap
    
    # Caido
    docker run -d \
        --name caido \
        --network "$DOCKER_NETWORK" \
        -p 8080:8080 \
        -v caido_data:/root/.config/caido \
        caido/caido

    # Metasploit
    docker run -d \
        --name metasploit \
        --network "$DOCKER_NETWORK" \
        -v msf_data:/home/msf/.msf4 \
        metasploitframework/metasploit-framework

    # Radare2
    docker run -d \
        --name radare2 \
        --network "$DOCKER_NETWORK" \
        -v radare2_data:/root/.radare2 \
        radare/radare2

    # DBBrowser
    docker run -d \
        --name dbbrowser \
        --network "$DOCKER_NETWORK" \
        -e DISPLAY="$DISPLAY" \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v pentest_data:/root/db \
        linuxserver/sqlitebrowser

    # JADX
    docker run -d \
        --name jadx \
        --network "$DOCKER_NETWORK" \
        -p 8070:8070 \
        -v jadx_data:/jadx \
        skylot/jadx

    # ADB
    docker run -d \
        --name adb \
        --network "$DOCKER_NETWORK" \
        --privileged \
        -v /dev/bus/usb:/dev/bus/usb \
        sorccu/adb

    # MobSF
    docker run -d \
        --name mobsf \
        --network "$DOCKER_NETWORK" \
        -p 8000:8000 \
        -v mobsf_data:/home/mobsf/.MobSF \
        opensecurity/mobile-security-framework-mobsf

    # Ghidra
    docker run -d \
        --name ghidra \
        --network "$DOCKER_NETWORK" \
        -e DISPLAY="$DISPLAY" \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v ghidra_data:/root/.ghidra \
        ghidra/ghidra

    setup_custom_containers
}

# Setup custom containers that need building
setup_custom_containers() {
    msg "${GREEN}[+] Setting up custom containers...${NC}"
    
    # RMS (Remote Mobile Security)
    setup_rms
    
    # iBlessing
    setup_iblessing
    
    # palera1n
    setup_palera1n
    
    # Additional Python tools
    msg "${GREEN}[+] Installing Python tools...${NC}"
    pip3 install --upgrade pip
    pip3 install frida-tools objection grapefruit
}

# Setup RMS
setup_rms() {
    msg "${GREEN}[+] Setting up RMS...${NC}"
    if [ ! -d "RMS" ]; then
        git clone https://github.com/m0bilesecurity/RMS || die "Failed to clone RMS"
    fi
    cd RMS || die "Failed to enter RMS directory"
    docker build -t rms .
    docker run -d \
        --name rms \
        --network "$DOCKER_NETWORK" \
        -p 5000:5000 \
        -v pentest_data:/data \
        rms
    cd ..
}

# Setup iBlessing
setup_iblessing() {
    msg "${GREEN}[+] Setting up iBlessing...${NC}"
    if [ ! -d "iblessing" ]; then
        git clone https://github.com/AloneMonkey/iblessing || die "Failed to clone iBlessing"
    fi
    cd iblessing || die "Failed to enter iBlessing directory"
    docker build -t iblessing - << 'EOF'
FROM ubuntu:20.04
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    libzip-dev \
    libssl-dev \
    git \
    && rm -rf /var/lib/apt/lists/*
COPY . /iblessing
WORKDIR /iblessing
RUN cmake . && make
ENTRYPOINT ["/iblessing/iblessing"]
EOF
    docker run -d \
        --name iblessing \
        --network "$DOCKER_NETWORK" \
        -v pentest_data:/data \
        iblessing
    cd ..
}

# Setup palera1n
setup_palera1n() {
    msg "${GREEN}[+] Setting up palera1n...${NC}"
    if [ ! -d "palera1n" ]; then
        git clone --recursive https://github.com/palera1n/palera1n || die "Failed to clone palera1n"
    fi
    cd palera1n || die "Failed to enter palera1n directory"
    docker build -t palera1n - << 'EOF'
FROM ubuntu:20.04
RUN apt-get update && apt-get install -y \
    libimobiledevice6 \
    usbmuxd \
    libusb-1.0-0 \
    git \
    make \
    && rm -rf /var/lib/apt/lists/*
COPY . /palera1n
WORKDIR /palera1n
RUN make
ENTRYPOINT ["/palera1n/palera1n"]
EOF
    docker run -d \
        --name palera1n \
        --network "$DOCKER_NETWORK" \
        --privileged \
        -v /dev/bus/usb:/dev/bus/usb \
        -v pentest_data:/data \
        palera1n
    cd ..
}

# Print container information
print_container_info() {
    msg "${GREEN}[+] Docker Network and Container Information:${NC}"
    echo "----------------------------------------"
    echo "Network: $DOCKER_NETWORK"
    docker network inspect "$DOCKER_NETWORK"
    
    msg "\n${GREEN}[+] Container Status:${NC}"
    docker ps -a
    
    msg "\n${GREEN}[+] Container IPs:${NC}"
    for container in $(docker ps -q); do
        echo "$(docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $container)"
    done
    
    msg "\n${GREEN}[+] Exposed Ports:${NC}"
    echo "Portainer: http://localhost:9000"
    echo "Caido: http://localhost:8080"
    echo "MobSF: http://localhost:8000"
    echo "JADX: http://localhost:8070"
    echo "RMS: http://localhost:5000"
}

# Cleanup function
cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    msg "${GREEN}[+] Cleaning up...${NC}"
    rm -rf RMS iblessing palera1n
    docker system prune -f
}

# Usage help
usage() {
    cat << EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v]

Pentest tools installation script.

Available options:
-h, --help      Print this help and exit
-v, --verbose   Print script debug info
EOF
    exit
}

# Parse parameters
parse_params() {
    while :; do
        case "${1-}" in
        -h | --help) usage ;;
        -v | --verbose) set -x ;;
        -?*) die "Unknown option: $1" ;;
        *) break ;;
        esac
        shift
    done
    return 0
}

# Main installation process
main() {
    parse_params "$@"
    setup_colors
    show_welcome
    check_root
    
    local os
    os=$(detect_os)
    msg "${BLUE}[i] Detected OS: $os${NC}"
    msg "${GREEN}[+] Starting installation process...${NC}"
    
    install_prerequisites "$os"
    create_user
    update_system "$os"
    install_system_apps "$os"
    install_docker "$os"
    setup_firewall
    configure_android_studio
    setup_docker_containers
    print_container_info
    
    msg "\n${GREEN}[✓] Installation complete!${NC}"
    msg "${BLUE}[i] Please log out and log back in as '${PHONERX_USER}' user to start using the tools.${NC}"
    msg "${BLUE}[i] All docker containers are connected to the '${DOCKER_NETWORK}' network.${NC}"
    msg "${BLUE}[i] Container management available through Portainer at http://localhost:9000${NC}"
}

# Run main function
main "$@"
