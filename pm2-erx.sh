#!/bin/bash

set -euo pipefail

readonly R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m' C='\033[0;36m' W='\033[1;37m' N='\033[0m'

VM_ID=""
VM_NAME=""
RAM_GB=""
SELECTED_STORAGE=""
QCOW2_PATH=""
DISK_SIZE_GB="65"

log() {
  echo -e "${B}[INFO]${N} $1"
}
success() {
  echo -e "${G}[OK]${N} $1"
}
warn() {
  echo -e "${Y}[WARN]${N} $1"
}
error() {
  echo -e "${R}[ERROR]${N} $1"
  exit 1
}

header() {
  clear
  echo -e "${C}┌─────────────────────────────────────────────────────────┐${N}"
  echo -e "${C}│${W}              Proxmox Metasploitable2 Creator            ${C}│${N}"
  echo -e "${C}└─────────────────────────────────────────────────────────┘${N}"
  echo
}

cleanup() {
  :
}

check_root() {
  [[ $EUID -eq 0 ]] || error "Run as root: sudo $0"
}
check_proxmox() {
  command -v qm >/dev/null || error "Not a Proxmox server (qm command missing)"
}

install_deps() {
  local deps=()
  for cmd in wget unzip bc qemu-img; do
    command -v "$cmd" >/dev/null || deps+=("${cmd/qemu-img/qemu-utils}")
  done
  if [[ ${#deps[@]} -gt 0 ]]; then
    log "Installing dependencies: ${deps[*]}"
    apt-get update -qq && apt-get install -y "${deps[@]}"
  fi
  success "Dependencies ready"
}

select_storage() {
  local storages=()
  mapfile -t storages < <(pvesm status --content images 2>/dev/null | awk 'NR>1 {print $1"|"$2"|"$6"|"$7}')
  [[ ${#storages[@]} -gt 0 ]] || error "No storage with 'images' support found"

  echo -e "${Y}Available Storage:${N}"
  printf "${C}┌───┬─────────────────┬─────────────┬─────────────┬─────────┐\n"
  printf "│ # │ Name            │ Type        │ Available   │ Used %%  │\n"
  printf "├───┼─────────────────┼─────────────┼─────────────┼─────────┤\n${N}"

  local i=1
  for storage in "${storages[@]}"; do
    IFS='|' read -r name type avail used <<<"$storage"
    printf "${C}│${N} %d ${C}│${N} %-15s ${C}│${N} %-11s ${C}│${N} %-11s ${C}│${N} %-7s ${C}│${N}\n" "$i" "$name" "$type" "$avail" "$used"
    ((i++))
  done
  printf "${C}└───┴─────────────────┴─────────────┴─────────────┴─────────┘\n${N}\n"

  while true; do
    read -p "$(echo -e "${Y}Select storage [1-${#storages[@]}]:${N}") " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#storages[@]})); then
      IFS='|' read -r SELECTED_STORAGE _ _ _ <<<"${storages[$((choice - 1))]}"
      success "Selected: $SELECTED_STORAGE"
      break
    else
      warn "Invalid choice. Please try again."
    fi
  done
}

get_user_input() {
  while true; do
    read -p "$(echo -e "\n${Y}Enter VM ID (100-999999999):${N}") " VM_ID
    if [[ "$VM_ID" =~ ^[0-9]+$ ]] && ((VM_ID >= 100 && VM_ID <= 999999999)); then
      if ! qm list | grep -q "^\s*$VM_ID\s"; then
        success "VM ID: $VM_ID"
        break
      fi
      warn "VM ID $VM_ID already exists"
    else
      warn "Invalid VM ID"
    fi
  done

  while true; do
    read -p "$(echo -e "\n${Y}Enter VM name:${N}") " VM_NAME
    if [[ -n "$VM_NAME" && "$VM_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      success "VM Name: $VM_NAME"
      break
    fi
    warn "Name must contain only letters, numbers, hyphens, underscores"
  done

  while true; do
    read -p "$(echo -e "\n${Y}Enter RAM in GB (minimum 1, recommended 2+):${N}") " RAM_GB
    if [[ "$RAM_GB" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (($(echo "$RAM_GB >= 1" | bc -l))); then
      success "RAM: ${RAM_GB}GB"
      break
    fi
    warn "Invalid RAM amount"
  done

  while true; do
    read -p "$(echo -e "\n${Y}Enter virtual disk size in GB (minimum 65):${N}") " DISK_SIZE_GB
    if [[ "$DISK_SIZE_GB" =~ ^[0-9]+$ ]] && ((DISK_SIZE_GB >= 65)); then
      success "Disk Size: ${DISK_SIZE_GB}GB"
      break
    fi
    warn "Invalid disk size. Must be an integer and at least 65 GB."
  done
}

prepare_metasploitable_image() {
  local vm_image_dir="/var/lib/vz/images/$VM_ID"
  log "Creating image directory: $vm_image_dir"
  mkdir -p "$vm_image_dir"
  cd "$vm_image_dir"

  log "Downloading Metasploitable2..."
  wget -q --show-progress "https://sourceforge.net/projects/metasploitable/files/Metasploitable2/metasploitable-linux-2.0.0.zip"

  log "Extracting archive..."
  unzip -q metasploitable-linux-2.0.0.zip

  log "Converting VMDK to qcow2 format..."
  qemu-img convert -O qcow2 Metasploitable2-Linux/Metasploitable.vmdk Metasploitable.qcow2

  log "Resizing QCOW2 image to ${DISK_SIZE_GB}GB..."
  qemu-img resize Metasploitable.qcow2 "${DISK_SIZE_GB}G"

  log "Cleaning up..."
  rm -rf Metasploitable2-Linux/ metasploitable-linux-2.0.0.zip

  QCOW2_PATH="$vm_image_dir/Metasploitable.qcow2"
  success "Image prepared at: $QCOW2_PATH"
}

create_and_configure_vm() {
  local ram_mb=$(($(echo "$RAM_GB * 1024" | bc | cut -d. -f1)))

  log "Creating empty VM $VM_ID..."
  qm create "$VM_ID" --name "$VM_NAME" --memory "$ram_mb" --cores 2 --net0 virtio,bridge=vmbr0 --ostype l26

  log "Importing disk to storage '$SELECTED_STORAGE'..."
  qm importdisk "$VM_ID" "$QCOW2_PATH" "$SELECTED_STORAGE"

  log "Attaching disk and setting boot order..."
  qm set "$VM_ID" --ide0 "${SELECTED_STORAGE}:vm-${VM_ID}-disk-0"
  qm set "$VM_ID" --boot c --bootdisk ide0

  log "Cleaning up source image file..."
  rm "$QCOW2_PATH"

  success "VM $VM_ID created and configured!"
}

show_summary_and_confirm() {
  echo -e "\n${C}┌─────────────────────────────────────────────────────────┐"
  echo -e "│${W}                    Configuration                        ${C}│"
  echo -e "├─────────────────────────────────────────────────────────┤"
  printf "│${N} VM ID    : %-45s ${C}│\n" "$VM_ID"
  printf "│${N} Name     : %-45s ${C}│\n" "$VM_NAME"
  printf "│${N} RAM      : %-45s ${C}│\n" "${RAM_GB}GB"
  printf "│${N} Disk Size: %-45s ${C}│\n" "${DISK_SIZE_GB}GB"
  printf "│${N} Storage  : %-45s ${C}│\n" "$SELECTED_STORAGE"
  echo -e "${C}└─────────────────────────────────────────────────────────┘${N}\n"

  read -p "$(echo -e "${Y}Create VM with these settings? [y/N]:${N}") " -n 1 confirm
  echo
  [[ "$confirm" =~ ^[Yy]$ ]] || {
    log "Cancelled."
    exit 0
  }
}

show_final_info() {
  echo
  success "VM creation complete!"
  echo -e "\n${W}Next steps:${N}"
  echo -e "  Start VM: ${G}qm start $VM_ID${N}"
  echo -e "  Console:  ${G}qm terminal $VM_ID${N}"
  echo -e "\n${W}Default credentials:${N}"
  echo -e "  Username: ${Y}msfadmin${N}"
  echo -e "  Password: ${Y}msfadmin${N}\n"
}

main() {
  trap cleanup EXIT
  header
  check_root
  check_proxmox
  install_deps

  select_storage
  get_user_input

  show_summary_and_confirm

  prepare_metasploitable_image
  create_and_configure_vm

  show_final_info
}

main "$@"
