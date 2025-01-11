#!/bin/bash

set -e 

handle_error() {
    echo "Error occurred in script at line $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

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
    echo "Pentest Toolset Installation Script"
    echo "-----------------------------------"
}

if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

create_user() {
    echo "[+] Creating phonerx user..."
    useradd -m -s /bin/bash phonerx
    echo "phonerx:phonerx" | chpasswd
    usermod -aG sudo phonerx
    usermod -aG docker phonerx
}

detect_os() {
    if [ -f /etc/arch-release ]; then
        echo "arch"
    elif [ -f /etc/lsb-release ]; then
        echo "ubuntu"
    else
        echo "unsupported"
    fi
}

update_system() {
    local os=$1
    echo "[+] Updating system..."
    if [ "$os" == "arch" ]; then
        pacman -Syu --noconfirm

        pacman -S --noconfirm snapd
        systemctl enable --now snapd.socket
        systemctl start snapd.service

        ln -s /var/lib/snapd/snap /snap
    elif [ "$os" == "ubuntu" ]; then
        apt update && apt upgrade -y

        if ! command -v snap &> /dev/null; then
            apt install -y snapd
            systemctl enable --now snapd.socket
            systemctl start snapd.service
        fi
    fi
    
    echo "[+] Waiting for snap service to initialize..."
    sleep 10
    snap wait system seed.loaded
}

install_system_apps() {
    local os=$1
    echo "[+] Installing system applications..."
    
    if [ "$os" == "arch" ]; then
        
        git clone https://aur.archlinux.org/yay.git
        cd yay
        makepkg -si --noconfirm
        cd ..
        rm -rf yay
        
        pacman -S --noconfirm code gcc
        
        pacman -S --noconfirm android-studio
        
        yay -S tabby-bin --noconfirm
        
        yay -S zen-browser --noconfirm
        
    elif [ "$os" == "ubuntu" ]; then

        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/vscode stable main" | tee /etc/apt/sources.list.d/vscode.list
        apt update
        apt install -y code g++
        
        add-apt-repository ppa:maarten-fonville/android-studio -y
        apt update
        apt install -y android-studio
        
        wget https://github.com/Eugeny/tabby/releases/latest/download/tabby-1.0.0-linux-x64.deb
        dpkg -i tabby-1.0.0-linux-x64.deb
        apt install -f -y
        
        snap install zen-browser
    fi
}


configure_android_studio() {
    echo "[+] Configuring Android Studio for Docker network..."
    mkdir -p /home/phonerx/.AndroidStudio
    cat > /home/phonerx/.AndroidStudio/docker.properties << EOF
docker.network=ptools-erx
docker.socket=/var/run/docker.sock
EOF
    chown -R phonerx:phonerx /home/phonerx/.AndroidStudio
}


setup_firewall() {
    echo "[+] Setting up UFW firewall..."
    apt install -y ufw
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    # Allow ports for various services
    ufw allow 8080/tcp  # Caido
    ufw allow 9000/tcp  # Portainer
    ufw allow 5037/tcp  # ADB
    ufw allow 8000/tcp  # MobSF
    ufw allow 5000/tcp  # RMS
    ufw allow 8070/tcp  # JADX
    ufw allow 3000/tcp  # Grapefruit
    ufw enable
}

install_docker() {
    local os=$1
    echo "[+] Installing Docker..."
    if [ "$os" == "arch" ]; then
        pacman -S --noconfirm docker docker-compose
    elif [ "$os" == "ubuntu" ]; then
        apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt update
        apt install -y docker-ce docker-ce-cli containerd.io docker-compose
    fi
    
    systemctl enable docker
    systemctl start docker

    docker network create ptools-erx
}


setup_docker_containers() {
    echo "[+] Setting up Docker containers..."

    docker volume create pentest_data

    # Portainer
    docker run -d \
        --name portainer \
        --network ptools-erx \
        --restart always \
        -p 9000:9000 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce

    # SQLMap
    docker run -d \
        --name sqlmap \
        --network ptools-erx \
        -v pentest_data:/root/.sqlmap \
        ahacking/sqlmap
    
    # Nmap
    docker run -d \
        --name nmap \
        --network ptools-erx \
        --cap-add=NET_ADMIN \
        --cap-add=NET_RAW \
        instrumentisto/nmap
    
    # Caido
    docker run -d \
        --name caido \
        --network ptools-erx \
        -p 8080:8080 \
        -v caido_data:/root/.config/caido \
        caido/caido

    # Metasploit
    docker run -d \
        --name metasploit \
        --network ptools-erx \
        -v msf_data:/home/msf/.msf4 \
        metasploitframework/metasploit-framework

    # Radare2
    docker run -d \
        --name radare2 \
        --network ptools-erx \
        -v radare2_data:/root/.radare2 \
        radare/radare2

    # DBBrowser
    docker run -d \
        --name dbbrowser \
        --network ptools-erx \
        -e DISPLAY=$DISPLAY \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v pentest_data:/root/db \
        linuxserver/sqlitebrowser

    # JADX
    docker run -d \
        --name jadx \
        --network ptools-erx \
        -p 8070:8070 \
        -v jadx_data:/jadx \
        skylot/jadx

    # ADB
    docker run -d \
        --name adb \
        --network ptools-erx \
        --privileged \
        -v /dev/bus/usb:/dev/bus/usb \
        sorccu/adb

    # MobSF
    docker run -d \
        --name mobsf \
        --network ptools-erx \
        -p 8000:8000 \
        -v mobsf_data:/home/mobsf/.MobSF \
        opensecurity/mobile-security-framework-mobsf

    # Ghidra
    docker run -d \
        --name ghidra \
        --network ptools-erx \
        -e DISPLAY=$DISPLAY \
        -v /tmp/.X11-unix:/tmp/.X11-unix \
        -v ghidra_data:/root/.ghidra \
        ghidra/ghidra

    # RMS
    echo "[+] Installing RMS..."
    if [ ! -d "RMS" ]; then
        git clone https://github.com/m0bilesecurity/RMS || {
            echo "Failed to clone RMS repository"
            return 1
        }
    fi
    cd RMS
    docker build -t rms .
    docker run -d \
        --name rms \
        --network ptools-erx \
        -p 5000:5000 \
        -v pentest_data:/data \
        rms
    cd ..

    # iBlessing
    echo "[+] Installing iBlessing..."
    if [ ! -d "iblessing" ]; then
        git clone https://github.com/AloneMonkey/iblessing || {
            echo "Failed to clone iBlessing repository"
            return 1
        }
    fi
    cd iblessing
    docker build -t iblessing - << EOF
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
        --network ptools-erx \
        -v pentest_data:/data \
        iblessing
    cd ..

    # palera1n
    echo "[+] Installing palera1n..."
    if [ ! -d "palera1n" ]; then
        git clone --recursive https://github.com/palera1n/palera1n || {
            echo "Failed to clone palera1n repository"
            return 1
        }
    fi
    cd palera1n
    docker build -t palera1n - << EOF
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
        --network ptools-erx \
        --privileged \
        -v /dev/bus/usb:/dev/bus/usb \
        -v pentest_data:/data \
        palera1n
    cd ..

    echo "[+] Installing additional tools..."
    
    # Frida
    pip3 install frida-tools
    
    # Objection
    pip3 install objection
    
    # Grapefruit
    pip3 install grapefruit
}

print_container_info() {
    echo "[+] Docker Network and Container Information:"
    echo "----------------------------------------"
    echo "Network: ptools-erx"
    docker network inspect ptools-erx
    
    echo -e "\nContainer Status:"
    docker ps -a
    
    echo -e "\nContainer IPs:"
    for container in $(docker ps -q); do
        echo "$(docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $container)"
    done
    
    echo -e "\nExposed Ports:"
    echo "Portainer: http://localhost:9000"
    echo "Caido: http://localhost:8080"
    echo "MobSF: http://localhost:8000"
    echo "JADX: http://localhost:8070"
    echo "RMS: http://localhost:5000"
}

cleanup() {
    echo "[+] Cleaning up installation files..."
    rm -rf RMS iblessing palera1n
    docker system prune -f
}


main() {
    show_welcome
    
    local os=$(detect_os)
    if [ "$os" == "unsupported" ]; then
        echo "Unsupported operating system"
        exit 1
    fi
    
    echo "Detected OS: $os"
    echo "Starting installation process..."
    
    create_user
    update_system "$os"
    install_system_apps "$os"
    install_docker "$os"
    setup_firewall
    configure_android_studio
    setup_docker_containers
    print_container_info
    cleanup
    
    echo -e "\nInstallation complete!"
    echo "Please log out and log back in as 'phonerx' user to start using the tools."
    echo "All docker containers are connected to the 'ptools-erx' network."
    echo "Container management available through Portainer at http://localhost:9000"
    echo "Much love from @non-erx"
}

main
