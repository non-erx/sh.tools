#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[1;34m'
ORANGE='\033[0;33m'
NC='\033[0m'

restart_script() {
    echo -e "\nRestarting..."
    sleep 1
    exec "$0"
}

clear
echo -e "${GREEN}docker managin tool. non-erx.dev. much love!${NC}"
echo -e "\----------------------------\\"

echo -e "${BLUE}IMAGES YOU HAVE:${NC}"
docker images

echo -e "\n${BLUE}DOCKER CONTAINERS:${NC}"
docker ps --all

echo -e "\n${BLUE}LIST OF THE NETWORKS:${NC}"
docker network ls

echo -e "\----------------------------\\"

while true; do
    echo -e "\nOPTIONS:"
    echo "1. Pull another image"
    echo "2. Create container using images"
    echo "3. Create a network and adjust connections"
    echo "4. Remove an image"
    echo "5. Remove a container"
    echo "6. Remove a network"
    echo "7. Shell 2 the container"
    echo "8. Exit"
    
    read -r -p "Enter your choice (1-8): " choice </dev/tty

    case $choice in
        1)
            read -r -p "What image you want to pull? " image_name </dev/tty
            echo -e "${ORANGE}docker pull ${image_name}${NC}"
            docker pull $image_name
            restart_script
            ;;
        2)
            read -r -p "What the name of the container? " container_name </dev/tty
            read -r -p "What the name of the image? " image_name </dev/tty
            read -r -p "What port do you want to use? " port </dev/tty
            echo -e "${ORANGE}docker run -d -it -p ${port}:${port} --name ${container_name} ${image_name}${NC}"
            docker run -d -it -p $port:$port --name $container_name $image_name
            restart_script
            ;;
        3)
            docker network ls
            read -r -p "Name for a new network: " network_name </dev/tty
            echo -e "${ORANGE}docker network create ${network_name}${NC}"
            docker network create $network_name
            
            read -r -p "Do you want to add containers to it? (Y/N) " add_containers </dev/tty
            
            if [[ $add_containers == "Y" || $add_containers == "y" ]]; then
                docker ps --all
                read -r -p "What containers do you want to add? (space-separated for multiple): " containers </dev/tty
                
                for container in $containers; do
                    echo -e "${ORANGE}docker network connect ${network_name} ${container}${NC}"
                    docker network connect $network_name $container
                done
            fi
            restart_script
            ;;
        4)
            docker images
            read -r -p "What image you want to remove? " image_name </dev/tty
            echo -e "${ORANGE}docker rmi ${image_name}${NC}"
            docker rmi $image_name
            restart_script
            ;;
        5)
            read -r -p "What container you want to remove? " container_name </dev/tty
            echo -e "${ORANGE}docker stop ${container_name}${NC}"
            docker stop $container_name
            echo -e "${ORANGE}docker rm ${container_name}${NC}"
            docker rm $container_name
            restart_script
            ;;
        6)
            read -r -p "Do you want remove all unused networks? (Y/N) " remove_all </dev/tty
            
            if [[ $remove_all == "Y" || $remove_all == "y" ]]; then
                echo -e "${ORANGE}docker network prune${NC}"
                docker network prune
            else
                docker network ls
                read -r -p "What network do u wanna remove? " network_name </dev/tty
                echo -e "${ORANGE}docker network rm ${network_name}${NC}"
                docker network rm $network_name
            fi
            restart_script
            ;;
        7)
            docker ps --all
            read -r -p "What container do you wanna login 2? " container_name </dev/tty
            echo -e "${ORANGE}docker container start ${container_name}${NC}"
            docker container start $container_name
            clear
            echo -e "${ORANGE}docker exec -it ${container_name} /bin/bash${NC}"
            docker exec -it $container_name /bin/bash
            clear
            exec "$0"
            ;;
        8)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option. Please try again."
            sleep 1
            restart_script
            ;;
    esac
done
