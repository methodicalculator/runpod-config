#!/bin/bash
# ============================================================
# Provisioning script personalizzato - AI-Dock Forge
# Basato su: https://github.com/ai-dock/stable-diffusion-webui-forge/blob/main/config/provisioning/default.sh
# Adattato 1:1 dalla struttura di provisioning.sh (A1111), stesso sistema
# di download Civitai/HF e stesse extensions. Nessun fix uv/constraints
# applicato per il momento: serve a testare se il conflitto NumPy si
# ripresenta anche su Forge.
#
# COME USARLO:
# 1. Sostituisci i placeholder qui sotto con i tuoi link Civitai/HF.
# 2. Carica questo file sul tuo repo GitHub (methodicalculator/runpod-config), branch main.
# 3. Nel template RunPod (immagine ghcr.io/ai-dock/stable-diffusion-webui-forge),
#    imposta la env var:
#      PROVISIONING_SCRIPT = https://raw.githubusercontent.com/<tuo-utente>/<tuo-repo>/main/provisioning-forge.sh
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

# --- Estensioni Forge da clonare in /extensions ---
EXTENSIONS=(
    "https://github.com/continue-revolution/sd-webui-segment-anything"
    "https://github.com/silveroxides/sd-webui-replacer"
    "https://codeberg.org/Gourieff/sd-webui-reactor"
)

# --- Checkpoint (SD1.5 + SDXL, vario) ---
# Sostituisci con gli URL "download" diretti di Civitai per i modelli che usi.
# Formato tipico Civitai: https://civitai.com/api/download/models/<VERSION_ID>
CHECKPOINT_MODELS=(
    "https://civitai.red/api/download/models/2574712"
)

# --- LoRA ---
LORA_MODELS=(
    ""
)

### NON MODIFICARE SOTTO QUESTA RIGA SE NON SAI COSA STAI FACENDO ###

# Costruisce URL Civitai a partire da una lista di ID separati da virgola,
# passata come env var da RunPod, e li aggiunge all'array indicato.
# Formato:
#   3117958   -> https://civitai.red/api/download/models/3117958
function provisioning_add_ids_to_array() {
    local -n target_array="$1"
    local ids_string="$2"
    [[ -z "$ids_string" ]] && return
    [[ "${ids_string,,}" == "replace_with_ids" ]] && return
    IFS=',' read -ra ids <<< "$ids_string"
    for id in "${ids[@]}"; do
        id="$(echo "$id" | xargs)" # trim spazi
        [[ -z "$id" ]] && continue
        target_array+=("https://civitai.red/api/download/models/${id}")
    done
}

function provisioning_start() {
    if [[ ! -d /opt/environments/python ]]; then
        export MAMBA_BASE=true
    fi
    source /opt/ai-dock/etc/environment.sh
    source /opt/ai-dock/bin/venv-set.sh webui

    # Aggiunge ai rispettivi array gli ID passati da RunPod come env var,
    # oltre a quelli già hardcoded sopra.
    provisioning_add_ids_to_array CHECKPOINT_MODELS "${CHECKPOINT_IDS_TO_DOWNLOAD}"
    provisioning_add_ids_to_array LORA_MODELS "${LORAS_IDS_TO_DOWNLOAD}"

    DISK_GB_AVAILABLE=$(($(df --output=avail -m "${WORKSPACE}" | tail -n1) / 1000))
    DISK_GB_USED=$(($(df --output=used -m "${WORKSPACE}" | tail -n1) / 1000))
    DISK_GB_ALLOCATED=$(($DISK_GB_AVAILABLE + $DISK_GB_USED))

    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_get_pip_packages
    provisioning_get_extensions
    provisioning_get_groundingdino_models
    provisioning_get_sam_models
    provisioning_get_reactor_models
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/ckpt" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_models \
        "${WORKSPACE}/storage/stable_diffusion/models/lora" \
        "${LORA_MODELS[@]}"
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
        path="/opt/stable-diffusion-webui-forge/extensions/${dir}"
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
    dir="/opt/stable-diffusion-webui-forge/extensions/sd-webui-segment-anything/models/grounding-dino"
    mkdir -p "$dir"
    if [[ ! -f "$dir/groundingdino_swint_ogc.pth" ]]; then
        printf "Downloading GroundingDINO model...\n"
        wget -qnc -P "$dir" "https://huggingface.co/ShilongLiu/GroundingDINO/resolve/main/groundingdino_swint_ogc.pth"
        wget -qnc -P "$dir" "https://raw.githubusercontent.com/IDEA-Research/GroundingDINO/main/groundingdino/config/GroundingDINO_SwinT_OGC.py"
    fi
}

function provisioning_get_sam_models() {
    dir="/opt/stable-diffusion-webui-forge/models/sam"
    mkdir -p "$dir"
    if [[ ! -f "$dir/sam_vit_l_0b3195.pth" ]]; then
        printf "Downloading SAM model for sd-webui-segment-anything...\n"
        wget -qnc -P "$dir" "https://dl.fbaipublicfiles.com/segment_anything/sam_vit_l_0b3195.pth"
    fi
}

function provisioning_get_reactor_models() {
    dir="/opt/stable-diffusion-webui-forge/models/insightface"
    mkdir -p "$dir"
    if [[ ! -f "$dir/inswapper_128.onnx" ]]; then
        printf "Downloading inswapper_128.onnx for ReActor...\n"
        wget -qnc -P "$dir" "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx"
    fi
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
