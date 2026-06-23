#!/bin/bash
# ============================================================
# Provisioning script personalizzato - AI-Dock ComfyUI
# Basato su: https://github.com/ai-dock/comfyui
#
# COME USARLO:
# 1. Sostituisci i placeholder qui sotto con i tuoi link Civitai/HF.
# 2. Carica questo file sul tuo repo GitHub (es. "runpod-config"), branch main,
#    con un nome diverso da quello usato per A1111 (es. "provisioning-comfyui.sh").
# 3. Nel template RunPod ComfyUI, imposta la env var:
#      PROVISIONING_SCRIPT = https://raw.githubusercontent.com/<tuo-utente>/<tuo-repo>/main/provisioning-comfyui.sh
# 4. Imposta anche CIVITAI_TOKEN con la tua API key Civitai.
# 5. Container image consigliata: ghcr.io/ai-dock/comfyui:latest-cuda
#    Porta HTTP da esporre: 8188 (ComfyUI), 1111 (Instance Portal), 8888 (Jupyter)
#    Porta TCP: 22 (SSH)
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

# --- Custom node ComfyUI da clonare in /custom_nodes ---
NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/storyicon/comfyui_segment_anything"
)

# --- Checkpoint (SD1.5 + SDXL, vario) ---
# Sostituisci con gli URL "download" diretti di Civitai per i modelli che usi.
# Formato tipico Civitai: https://civitai.com/api/download/models/<VERSION_ID>
CHECKPOINT_MODELS=(
    "https://civitai.red/api/download/models/2574712"
    "https://civitai.red/api/download/models/2551619"
)

# --- LoRA ---
LORA_MODELS=(
    ""
)

# --- VAE ---
VAE_MODELS=(
    ""
)

# --- Upscaler ---
ESRGAN_MODELS=(
    ""
)

# --- ControlNet (lascia vuoto, gestite a parte) ---
CONTROLNET_MODELS=(
    ""
)

### NON MODIFICARE SOTTO QUESTA RIGA SE NON SAI COSA STAI FACENDO ###

function provisioning_start() {
    if [[ ! -d /opt/environments/python ]]; then
        export MAMBA_BASE=true
    fi
    source /opt/ai-dock/etc/environment.sh
    source /opt/ai-dock/bin/venv-set.sh comfyui

    DISK_GB_AVAILABLE=$(($(df --output=avail -m "${WORKSPACE}" | tail -n1) / 1000))
    DISK_GB_USED=$(($(df --output=used -m "${WORKSPACE}" | tail -n1) / 1000))
    DISK_GB_ALLOCATED=$(($DISK_GB_AVAILABLE + $DISK_GB_USED))

    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_get_pip_packages
    provisioning_get_nodes
    provisioning_get_segment_anything_models
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/loras" \
        "${LORA_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/upscale_models" \
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

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        [[ -z "$repo" ]] && continue
        dir="${repo##*/}"
        path="/opt/ComfyUI/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${AUTOUPDATE,,} == "true" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                ( cd "$path" && git pull )
                if [[ -e $requirements ]]; then
                    pip install --no-cache-dir -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e $requirements ]]; then
                pip install --no-cache-dir -r "$requirements"
            fi
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

function provisioning_get_segment_anything_models() {
    # comfyui_segment_anything (storyicon) - equivalente ComfyUI di
    # sd-webui-segment-anything. Path relativi alla root di ComfyUI:
    # models/grounding-dino e models/sams.
    dino_dir="/opt/ComfyUI/models/grounding-dino"
    sam_dir="/opt/ComfyUI/models/sams"
    mkdir -p "$dino_dir" "$sam_dir"
    if [[ ! -f "$dino_dir/groundingdino_swint_ogc.pth" ]]; then
        printf "Downloading GroundingDINO model...\n"
        wget -qnc -P "$dino_dir" "https://huggingface.co/ShilongLiu/GroundingDINO/resolve/main/groundingdino_swint_ogc.pth"
        wget -qnc -P "$dino_dir" "https://raw.githubusercontent.com/IDEA-Research/GroundingDINO/main/groundingdino/config/GroundingDINO_SwinT_OGC.py"
    fi
    if [[ ! -f "$sam_dir/sam_vit_l_0b3195.pth" ]]; then
        printf "Downloading SAM model...\n"
        wget -qnc -P "$sam_dir" "https://dl.fbaipublicfiles.com/segment_anything/sam_vit_l_0b3195.pth"
    fi
}

function provisioning_print_end() {
    printf "\nProvisioning complete: ComfyUI will start now\n\n"
}

function provisioning_download() {
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9-]+\.)?civitai\.(com|red)(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi
    if [[ -n $auth_token && $1 =~ civitai\.(com|red) ]]; then
        # Civitai: l'header Authorization non deve essere propagato al
        # redirect verso il bucket Cloudflare R2 (causa 400 Bad Request).
        # Risolviamo prima il redirect manualmente con il token, poi
        # scarichiamo dall'URL pre-firmato senza alcun header extra.
        real_url=$(wget --header="Authorization: Bearer $auth_token" --max-redirect=0 "$1" 2>&1 | grep -o "Location: .*" | sed 's/Location: //' | sed 's/ \[following\]//')
        if [[ -n "$real_url" ]]; then
            wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$real_url"
        else
            printf "WARNING: Could not resolve Civitai redirect for %s, trying direct download...\n" "$1"
            wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
        fi
    elif [[ -n $auth_token ]]; then
        wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    fi
}

provisioning_start
