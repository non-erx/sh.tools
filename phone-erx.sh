# /bin/bash

# Script settings
set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

# Script variables
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
PHONERX_USER="phonerx"
PHONERX_PASS="phonerx"
DOCKER_NETWORK="ptools-erx"

# Color definitions (no readonly)
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Show ASCII banner
show_banner() {
    clear
    cat << "EOF"
    ██████╗ ██╗  ██╗ ██████╗ ███╗   ██╗███████╗   ███████╗██████╗ ██╗  ██╗
    ██╔══██╗██║  ██║██╔═══██╗████╗  ██║██╔════╝   ██╔════╝██╔══██╗╚██╗██╔╝
    ██████╔╝███████║██║   ██║██╔██╗ ██║█████╗     █████╗  ██████╔╝ ╚███╔╝ 
    ██╔═══╝ ██╔══██║██║   ██║██║╚██╗██║██╔══╝     ██╔══╝  ██╔══██╗ ██╔██╗ 
    ██║     ██║  ██║╚██████╔╝██║ ╚████║███████╗   ███████╗██║  ██║██╔╝ ██╗
    ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝
                                                                by @non-erx
EOF
    echo -e "\n${BLUE}Pentest Toolset Installation Script${NC}"
    echo "-----------------------------------"
}

# Message functions
msg() { echo -e "${1-}"; }
info() { msg "${BLUE}[i] ${1}${NC}"; }
success() { msg "${GREEN}[+] ${1}${NC}"; }
error() { msg "${RED}[✗] ${1}${NC}"; exit 1; }

# Check root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "\nThis script requires root privileges for:"
        echo "- Installing system packages and dependencies"
        echo "- Creating new user accounts"
        echo "- Configuring Docker and network settings"
        echo "- Setting up firewall rules"
        echo "- Managing system services"
        
        read -r -p "Would you like to run this script with sudo? (Y/N): " choice </dev/tty
        case $choice in
            [Yy]*)
                exec sudo bash "$0" "$@"
                ;;
            [Nn]*)
                echo "Exiting..."
                exit 1
                ;;
            *)
                echo "Invalid choice. Please answer Y or N."
                exit 1
                ;;
        esac
    fi
}

# Check and install Docker first
install_docker() {
    success "Installing Docker..."
    local os=$1
    
    if ! command -v docker &>/dev/null; then
        if [ "$os" == "arch" ]; then
            pacman -S --noconfirm docker docker-compose
        elif [ "$os" == "ubuntu" ]; then
            apt update
            apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt update
            apt install -y docker-ce docker-ce-cli containerd.io docker-compose
        fi
    fi
    
    systemctl enable docker
    systemctl start docker
    docker network create "$DOCKER_NETWORK" 2>/dev/null || true
}

# Detect OS
detect_os() {
    if [ -f /etc/arch-release ]; then
        echo "arch"
    elif [ -f /etc/lsb-release ]; then
        echo "ubuntu"
    else
        error "Unsupported operating system"
    fi
}

# Install prerequisites
install_prerequisites() {
    local os=$1
    success "Installing prerequisites..."
    if [ "$os" == "ubuntu" ]; then
        rm -rf snapd
        apt update
        apt install -y curl wget git python3-pip software-properties-common snapd ufw
    elif [ "$os" == "arch" ]; then
        rm -rf snapd
        pacman -Syu --noconfirm
        pacman -S --noconfirm curl wget git python-pip ufw
        git clone https://aur.archlinux.org/snapd-git.git
        cd snapd
        makepkg -si
    fi
}

# Create user
create_user() {
    success "Creating user ${PHONERX_USER}..."
    if ! id "$PHONERX_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$PHONERX_USER"
        echo "${PHONERX_USER}:${PHONERX_PASS}" | chpasswd
        usermod -aG sudo "$PHONERX_USER"
        usermod -aG docker "$PHONERX_USER"
    fi
}

# Configure system applications
setup_system_apps() {
    local os=$1
    success "Setting up system applications..."
    
    if [ "$os" == "arch" ]; then
        if ! command -v yay &>/dev/null; then
            git clone https://aur.archlinux.org/yay.git
            cd yay || error "Failed to enter yay directory"
            makepkg -si --noconfirm
            cd .. && rm -rf yay
        fi
        
        pacman -S --noconfirm code gcc android-studio
        yay -S --noconfirm tabby-bin zen-browser
        
    elif [ "$os" == "ubuntu" ]; then
        # VSCode
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/vscode stable main" | tee /etc/apt/sources.list.d/vscode.list > /dev/null
        apt update && apt install -y code g++
        
        # Android Studio
        add-apt-repository ppa:maarten-fonville/android-studio -y
        apt update && apt install -y android-studio
        
        # Tabby
        rm -rf tabby-1.0.219-linux-arm64.deb
        wget "https://github.com/Eugeny/tabby/releases/download/v1.0.219/tabby-1.0.219-linux-arm64.deb"
        sudo dpkg -i tabby-1.0.219-linux-arm64.deb | sudo apt instal -f -y
        rm tabby-1.0.219-linux-arm64.deb
        
        # Zen Browser
        snap install zen-browser
    fi
}

# Configure Android Studio
configure_android_studio() {
    success "Configuring Android Studio..."
    local config_dir="/home/${PHONERX_USER}/.AndroidStudio"
    mkdir -p "$config_dir"
    cat > "${config_dir}/docker.properties" << EOF
docker.network=${DOCKER_NETWORK}
docker.socket=/var/run/docker.sock
EOF
    chown -R "${PHONERX_USER}:${PHONERX_USER}" "$config_dir"
}

# Setup firewall
setup_firewall() {
    success "Setting up firewall..."
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

# Setup base containers
setup_base_containers() {
    success "Setting up base containers..."
    
    # Create volumes
    docker volume create pentest_data
    docker volume create portainer_data
    docker volume create msf_data
    docker volume create caido_data

    # Portainer
    docker run -d \
        --name portainer \
        --network "$DOCKER_NETWORK" \
        --restart always \
        -p 9000:9000 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce

    # Common pentesting tools
    declare -A containers=(
        ["sqlmap"]="ahacking/sqlmap:-d --name sqlmap --network $DOCKER_NETWORK -v pentest_data:/root/.sqlmap"
        ["nmap"]="instrumentisto/nmap:-d --name nmap --network $DOCKER_NETWORK --cap-add=NET_ADMIN --cap-add=NET_RAW"
        ["metasploit"]="metasploitframework/metasploit-framework:-d --name metasploit --network $DOCKER_NETWORK -v msf_data:/home/msf/.msf4"
        ["caido"]="caido/caido:-d --name caido --network $DOCKER_NETWORK -p 8080:8080 -v caido_data:/root/.config/caido"
        ["mobsf"]="opensecurity/mobile-security-framework-mobsf:-d --name mobsf --network $DOCKER_NETWORK -p 8000:8000"
        ["jadx"]="skylot/jadx:-d --name jadx --network $DOCKER_NETWORK -p 8070:8070"
    )

    for name in "${!containers[@]}"; do
        IFS=':' read -r image opts <<< "${containers[$name]}"
        success "Starting $name..."
        docker run $opts $image
    done
}

# Setup custom containers
setup_custom_containers() {
    success "Setting up custom containers..."
    
    # RMS
    git clone https://github.com/m0bilesecurity/RMS
    cd RMS || error "Failed to enter RMS directory"
    docker build -t rms .
    docker run -d \
        --name rms \
        --network "$DOCKER_NETWORK" \
        -p 5000:5000 \
        -v pentest_data:/data \
        rms
    cd ..

    # iBlessing
    git clone https://github.com/AloneMonkey/iblessing
    cd iblessing || error "Failed to enter iBlessing directory"
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

    # palera1n
    git clone --recursive https://github.com/palera1n/palera1n
    cd palera1n || error "Failed to enter palera1n directory"
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

    # Additional tools
    pip3 install --upgrade pip
    pip3 install frida-tools objection grapefruit
}

# Print container information
print_info() {
    success "Installation Summary:"
    echo "----------------------------------------"
    echo "Network: $DOCKER_NETWORK"
    
    success "Container Status:"
    docker ps -a
    
    success "Container IPs:"
    for container in $(docker ps -q); do
        echo "$(docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $container)"
    done
    
    success "Web Interfaces:"
    echo "Portainer: http://localhost:9000"
    echo "Caido: http://localhost:8080"
    echo "MobSF: http://localhost:8000"
    echo "JADX: http://localhost:8070"
    echo "RMS: http://localhost:5000"
}

# Cleanup function
cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    success "Cleaning up..."
    rm -rf RMS iblessing palera1n
}

# Main function
main() {
    show_banner
    check_root
    
    local os
    os=$(detect_os)
    info "Detected OS: $os"
    
    # Initial setup
    install_prerequisites "$os"
    install_docker "$os"
    
    # Verify Docker
    if ! command -v docker &>/dev/null; then
        error "Docker installation failed"
    fi
    
    # Continue with installation
    create_user
    setup_system_apps "$os"
    configure_android_studio
    setup_firewall
    setup_base_containers
    setup_custom_containers
    print_info
    
    success "Installation complete!"
    info "Please log out and log back in as '$PHONERX_USER' to start using the tools."
    info "Container management available at http://localhost:9000"
}

# Start installation
main "$@"
