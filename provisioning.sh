#!/bin/bash
# ============================================================
# Provisioning script personalizzato - AI-Dock A1111
# Basato su: https://github.com/ai-dock/stable-diffusion-webui/blob/main/config/provisioning/default.sh
#
# COME USARLO:
# 1. Sostituisci i placeholder qui sotto con i tuoi link Civitai/HF.
# 2. Carica questo file su un tuo repo GitHub (es. "runpod-config"), branch main.
# 3. Nel template RunPod, imposta la env var:
#      PROVISIONING_SCRIPT = https://raw.githubusercontent.com/<tuo-utente>/<tuo-repo>/main/provisioning.sh
# 4. Imposta anche la env var CIVITAI_TOKEN con la tua API key Civitai
#    (così i download autenticati funzionano anche per modelli che la richiedono).
# ============================================================

DISK_GB_REQUIRED=40

# --- Pacchetti di sistema extra (lascia vuoto se non servono) ---
APT_PACKAGES=(
    ""
)

# --- Pacchetti python extra (lascia vuoto se non servono) ---
PIP_PACKAGES=(
    ""
)

# --- Estensioni A1111 da clonare in /extensions ---
EXTENSIONS=(
    "https://github.com/Uminosachi/sd-webui-inpaint-anything"
)

# --- Checkpoint (SD1.5 + SDXL, vario) ---
# Sostituisci con gli URL "download" diretti di Civitai per i modelli che usi.
# Formato tipico Civitai: https://civitai.com/api/download/models/<VERSION_ID>
CHECKPOINT_MODELS=(
    "https://civitai.com/api/download/models/302254"
)

# --- LoRA ---
LORA_MODELS=(
    ""
)

# --- VAE ---
VAE_MODELS=(
    ""
)

# --- Upscaler ESRGAN ---
ESRGAN_MODELS=(
    ""
)

# --- ControlNet (lascia vuoto, hai detto che gestisci queste a parte) ---
CONTROLNET_MODELS=(
    ""
)

### NON MODIFICARE SOTTO QUESTA RIGA SE NON SAI COSA STAI FACENDO ###

function provisioning_start() {
    if [[ ! -d /opt/environments/python ]]; then
        export MAMBA_BASE=true
    fi
    source /opt/ai-dock/etc/environment.sh
    source /opt/ai-dock/bin/venv-set.sh webui

    DISK_GB_AVAILABLE=$(($(df --output=avail -m "${WORKSPACE}" | tail -n1) / 1000))
    DISK_GB_USED=$(($(df --output=used -m "${WORKSPACE}" | tail -n1) / 1000))
    DISK_GB_ALLOCATED=$(($DISK_GB_AVAILABLE + $DISK_GB_USED))

    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_get_pip_packages
    provisioning_get_extensions
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/ckpt" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/lora" \
        "${LORA_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/esrgan" \
        "${ESRGAN_MODELS[@]}"
    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
        sudo "$APT_INSTALL" "${APT_PACKAGES[@]}"
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
        pip install --no-cache-dir "${PIP_PACKAGES[@]}"
    fi
}

function provisioning_get_extensions() {
    for repo in "${EXTENSIONS[@]}"; do
        [[ -z "$repo" ]] && continue
        dir="${repo##*/}"
        path="/opt/stable-diffusion-webui/extensions/${dir}"
        if [[ -d $path ]]; then
            if [[ ${AUTOUPDATE,,} == "true" ]]; then
                printf "Updating extension: %s...\n" "${repo}"
                ( cd "$path" && git pull )
            fi
        else
            printf "Downloading extension: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
        fi
    done
}

function provisioning_get_models() {
    if [[ -z $2 ]]; then return 1; fi
    dir="$1"
    mkdir -p "$dir"
    shift
    if [[ $DISK_GB_ALLOCATED -ge $DISK_GB_REQUIRED ]]; then
        arr=("$@")
    else
        printf "WARNING: Low disk space allocation - Only the first model will be downloaded!\n"
        arr=("$1")
    fi
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        [[ -z "$url" ]] && continue
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete: Web UI will start now\n\n"
}

function provisioning_download() {
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi
    if [[ -n $auth_token ]]; then
        wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    fi
}

provisioning_start
