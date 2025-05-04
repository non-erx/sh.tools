#!/bin/bash

# Check if script is run with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo privileges."
  exit 1
fi

# Function to validate IP address
validate_ip() {
  local ip=$1
  local stat=1

  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    OIFS=$IFS
    IFS='.'
    ip=($ip)
    IFS=$OIFS
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
    stat=$?
  fi
  return $stat
}

# Function to validate CIDR notation
validate_cidr() {
  local cidr=$1
  local ip=$(echo $cidr | cut -d'/' -f1)
  local prefix=$(echo $cidr | cut -d'/' -f2)
  
  # Validate IP part
  validate_ip "$ip"
  if [ $? -ne 0 ]; then
    return 1
  fi
  
  # Validate prefix part
  if ! [[ "$prefix" =~ ^[0-9]+$ ]] || [ "$prefix" -lt 1 ] || [ "$prefix" -gt 32 ]; then
    return 1
  fi
  
  return 0
}

# Function to get user input with default value
get_input_with_default() {
  local prompt=$1
  local default=$2
  local input
  
  read -p "$prompt [$default]: " input
  echo ${input:-$default}
}

# Function to get yes/no input
get_yes_no() {
  local prompt=$1
  local default=$2
  local input
  
  while true; do
    read -p "$prompt (y/n) [$default]: " input
    input=${input:-$default}
    case $input in
      [Yy]* ) echo "yes"; return ;;
      [Nn]* ) echo "no"; return ;;
      * ) echo "Please answer yes (y) or no (n)." ;;
    esac
  done
}

echo "=== Netplan Static IP Configuration Tool ==="
echo

# Find all netplan configuration files
netplan_dir="/etc/netplan"
netplan_files=($(ls $netplan_dir/*.yaml 2>/dev/null))
num_files=${#netplan_files[@]}

if [ $num_files -eq 0 ]; then
  echo "No Netplan configuration files found in $netplan_dir."
  echo "Creating a new configuration file..."
  new_file="$netplan_dir/01-netcfg.yaml"
  echo "# Netplan configuration created by setup script" > "$new_file"
  echo "network:" >> "$new_file"
  echo "  version: 2" >> "$new_file"
  echo "  ethernets:" >> "$new_file"
  netplan_files=("$new_file")
  selected_file="$new_file"
  echo "Created new file: $new_file"
elif [ $num_files -eq 1 ]; then
  selected_file=${netplan_files[0]}
  echo "Found one Netplan configuration file: $selected_file"
else
  echo "Found multiple Netplan configuration files:"
  for i in "${!netplan_files[@]}"; do
    echo "  $((i+1)). ${netplan_files[$i]}"
  done
  
  while true; do
    read -p "Select a file (1-$num_files): " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le $num_files ]; then
      selected_file=${netplan_files[$((selection-1))]}
      break
    else
      echo "Invalid selection. Please enter a number between 1 and $num_files."
    fi
  done
fi

echo "Using configuration file: $selected_file"
echo

# Parse the selected file to find network interfaces
# This improved version correctly extracts only the interface names
interfaces=()

# Use a more precise grep pattern to extract interface names under ethernets section
while read -r line; do
  # Remove leading whitespace
  trimmed_line=$(echo "$line" | sed -e 's/^[[:space:]]*//')
  # Check if this line is directly under ethernets: and has a colon at the end
  if [[ $trimmed_line =~ ^([a-zA-Z0-9_-]+):$ ]]; then
    interfaces+=(${BASH_REMATCH[1]})
  fi
done < <(grep -A50 "ethernets:" "$selected_file" | grep -v "ethernets:" | grep -v "^#" | grep -v "^$")

# If no interfaces found, try to detect them from the system
if [ ${#interfaces[@]} -eq 0 ]; then
  echo "No interfaces found in the configuration file."
  echo "Detecting available network interfaces..."
  
  # Get all interfaces except lo
  available_interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo))
  
  if [ ${#available_interfaces[@]} -eq 0 ]; then
    echo "No network interfaces detected on the system."
    exit 1
  elif [ ${#available_interfaces[@]} -eq 1 ]; then
    interfaces=(${available_interfaces[0]})
    echo "Found one network interface: ${interfaces[0]}"
  else
    echo "Found multiple network interfaces:"
    for i in "${!available_interfaces[@]}"; do
      echo "  $((i+1)). ${available_interfaces[$i]}"
    done
    
    while true; do
      read -p "Select an interface (1-${#available_interfaces[@]}): " selection
      if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#available_interfaces[@]} ]; then
        interfaces=(${available_interfaces[$((selection-1))]})
        break
      else
        echo "Invalid selection. Please enter a number between 1 and ${#available_interfaces[@]}."
      fi
    done
  fi
else
  if [ ${#interfaces[@]} -eq 1 ]; then
    echo "Found one interface in the configuration: ${interfaces[0]}"
  else
    echo "Found multiple interfaces in the configuration:"
    for i in "${!interfaces[@]}"; do
      echo "  $((i+1)). ${interfaces[$i]}"
    done
    
    while true; do
      read -p "Select an interface to configure (1-${#interfaces[@]}): " selection
      if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#interfaces[@]} ]; then
        selected_interface=${interfaces[$((selection-1))]}
        interfaces=("$selected_interface")
        break
      else
        echo "Invalid selection. Please enter a number between 1 and ${#interfaces[@]}."
      fi
    done
  fi
fi

interface=${interfaces[0]}
echo "Configuring interface: $interface"
echo

# Ask for DHCP configuration
dhcp_enabled=$(get_yes_no "Do you want to enable DHCP" "n")

# Configuration variables
addresses=()
gateway=""
nameservers=()
search_domains=()

if [ "$dhcp_enabled" = "no" ]; then
  # Static IP configuration
  echo "Configuring static IP address..."
  
  # Get IP address with CIDR notation
  while true; do
    read -p "Enter IP address with CIDR notation (e.g., 10.42.0.45/24): " ip_cidr
    if validate_cidr "$ip_cidr"; then
      addresses+=("$ip_cidr")
      break
    else
      echo "Invalid IP address or CIDR notation. Please try again."
    fi
  done
  
  # Get gateway
  while true; do
    read -p "Enter gateway IP address: " gateway
    if validate_ip "$gateway"; then
      break
    else
      echo "Invalid IP address. Please try again."
    fi
  done
  
  # Get DNS servers
  echo "Enter DNS server IP addresses (leave empty to finish):"
  while true; do
    read -p "DNS server IP: " dns
    if [ -z "$dns" ]; then
      break
    elif validate_ip "$dns"; then
      nameservers+=("$dns")
    else
      echo "Invalid IP address. Please try again."
    fi
  done
  
  # If no DNS servers provided, use default ones
  if [ ${#nameservers[@]} -eq 0 ]; then
    nameservers+=("8.8.8.8" "8.8.4.4")
    echo "Using default DNS servers: 8.8.8.8, 8.8.4.4"
  fi
  
  # Ask for search domains
  add_search_domains=$(get_yes_no "Do you want to add search domains" "n")
  if [ "$add_search_domains" = "yes" ]; then
    echo "Enter search domains (leave empty to finish):"
    while true; do
      read -p "Search domain: " domain
      if [ -z "$domain" ]; then
        break
      else
        search_domains+=("$domain")
      fi
    done
  fi
fi

# Create a temporary file for the new configuration
temp_file=$(mktemp)

# Write the new configuration
cat > "$temp_file" << EOF
# This file was generated by the Netplan configuration script
network:
  version: 2
  ethernets:
    $interface:
EOF

if [ "$dhcp_enabled" = "yes" ]; then
  echo "      dhcp4: true" >> "$temp_file"
else
  echo "      dhcp4: false" >> "$temp_file"
  
  # Add addresses
  if [ ${#addresses[@]} -gt 0 ]; then
    echo "      addresses:" >> "$temp_file"
    for addr in "${addresses[@]}"; do
      echo "        - $addr" >> "$temp_file"
    done
  fi
  
  # Add gateway
  if [ ! -z "$gateway" ]; then
    echo "      routes:" >> "$temp_file"
    echo "        - to: default" >> "$temp_file"
    echo "          via: $gateway" >> "$temp_file"
  fi
  
  # Add DNS servers
  if [ ${#nameservers[@]} -gt 0 ]; then
    echo "      nameservers:" >> "$temp_file"
    echo "        addresses:" >> "$temp_file"
    for ns in "${nameservers[@]}"; do
      echo "          - $ns" >> "$temp_file"
    done
    
    # Add search domains
    if [ ${#search_domains[@]} -gt 0 ]; then
      echo "        search:" >> "$temp_file"
      for domain in "${search_domains[@]}"; do
        echo "          - $domain" >> "$temp_file"
      done
    fi
  fi
fi

# Show the new configuration
echo
echo "New configuration:"
echo "===================="
cat "$temp_file"
echo "===================="
echo

# Save the configuration
cp "$temp_file" "$selected_file"
rm "$temp_file"
echo "Configuration saved to $selected_file"

# Apply the configuration
apply_config=$(get_yes_no "Do you want to apply the configuration now" "y")
if [ "$apply_config" = "yes" ]; then
  echo "Applying configuration..."
  netplan apply
  echo "Configuration applied successfully."
  
  # Show the new IP configuration
  echo
  echo "Current network configuration:"
  ip addr show $interface
else
  echo "Configuration not applied. You can apply it later with 'sudo netplan apply'."
fi

echo
echo "Configuration complete!"
