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
    "https://github.com/continue-revolution/sd-webui-segment-anything"
    "https://github.com/silveroxides/sd-webui-replacer"
    "https://codeberg.org/Gourieff/sd-webui-reactor"
)

# --- Checkpoint (SD1.5 + SDXL, vario) ---
# Sostituisci con gli URL "download" diretti di Civitai per i modelli che usi.
# Formato tipico Civitai: https://civitai.com/api/download/models/<VERSION_ID>
CHECKPOINT_MODELS=(
    "https://civitai.red/api/download/models/302254"
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
    provisioning_get_groundingdino_models
    provisioning_get_sam_models
    provisioning_get_reactor_model
    provisioning_fix_reactor_deps
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

function provisioning_get_groundingdino_models() {
    dir="/opt/stable-diffusion-webui/extensions/sd-webui-segment-anything/models/grounding-dino"
    mkdir -p "$dir"
    if [[ ! -f "$dir/groundingdino_swint_ogc.pth" ]]; then
        printf "Downloading GroundingDINO model...\n"
        wget -qnc -P "$dir" "https://huggingface.co/ShilongLiu/GroundingDINO/resolve/main/groundingdino_swint_ogc.pth"
        wget -qnc -P "$dir" "https://raw.githubusercontent.com/IDEA-Research/GroundingDINO/main/groundingdino/config/GroundingDINO_SwinT_OGC.py"
    fi
}

function provisioning_get_sam_models() {
    dir="/opt/stable-diffusion-webui/models/sam"
    mkdir -p "$dir"
    if [[ ! -f "$dir/sam_vit_l_0b3195.pth" ]]; then
        printf "Downloading SAM model for sd-webui-segment-anything...\n"
        wget -qnc -P "$dir" "https://dl.fbaipublicfiles.com/segment_anything/sam_vit_l_0b3195.pth"
    fi
}

function provisioning_get_reactor_model() {
    dir="/opt/stable-diffusion-webui/models/insightface"
    mkdir -p "$dir"
    if [[ ! -f "$dir/inswapper_128.onnx" ]]; then
        printf "Downloading ReActor inswapper model...\n"
        wget -qnc -P "$dir" "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx"
    fi
}

function provisioning_fix_reactor_deps() {
    printf "Fixing ReActor dependencies (numpy/onnxruntime compatibility)...\n"
    # NON toccare la versione di numpy: torch/xformers in questo ambiente
    # sono compilati per NumPy 2.x. Il conflitto va risolto aggiornando
    # onnxruntime-gpu a una build compatibile con NumPy 2.x, non
    # retrocedendo numpy.
    pip install --no-cache-dir --upgrade "onnxruntime-gpu>=1.19.0" "insightface==0.7.3" "albumentations==1.4.3"
}

function provisioning_print_end() {
    printf "\nProvisioning complete: Web UI will start now\n\n"
}

function provisioning_download() {
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9-]+\.)?civitai\.(com|red)(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi
    if [[ -n $auth_token ]]; then
        wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    fi
}

provisioning_start
