#!/bin/bash
# ============================================================
# Script di avvio ComfyUI standalone (no AI-Dock)
# Repo ufficiale: https://github.com/Comfy-Org/ComfyUI
#
# COME USARLO:
# 1. Imposta questo file come Container Start Command su RunPod
#    (oppure caricalo sul repo e richiamalo da lì).
# 2. Monta un Network Volume su /workspace per persistenza tra riavvii.
# 3. Env var opzionali da impostare su RunPod:
#      CIVITAI_TOKEN            -> la tua API key Civitai
#      HF_TOKEN                 -> token Hugging Face, se serve
#      COMFYUI_REF               -> "master" (default) o un tag di release
#                                    tipo "v0.22.0" per restare pinnato
#                                    a una versione stabile
#      CHECKPOINT_IDS_TO_DOWNLOAD -> ID versione Civitai separati da virgola
#      LORAS_IDS_TO_DOWNLOAD      -> ID versione Civitai separati da virgola
#                                    (metti "false" o "skip" per disattivare)
# ============================================================

WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_DIR="${WORKSPACE}/ComfyUI"
COMFYUI_REF="${COMFYUI_REF:-master}"

# --- Checkpoint fissi (opzionali, si sommano a quelli via env var) ---
CHECKPOINT_MODELS=(
    ""
)

# --- LoRA fissi (opzionali, si sommano a quelli via env var) ---
LORA_MODELS=(
    ""
)

### NON MODIFICARE SOTTO QUESTA RIGA SE NON SAI COSA STAI FACENDO ###

# Costruisce URL Civitai a partire da una lista di ID separati da virgola,
# passata come env var da RunPod, e li aggiunge all'array indicato.
# Formato: 3117958 -> https://civitai.red/api/download/models/3117958
function provisioning_add_ids_to_array() {
    local -n target_array="$1"
    local ids_string="$2"
    [[ -z "$ids_string" ]] && return
    case "${ids_string,,}" in
        "replace_with_ids"|"false"|"skip"|"none") return ;;
    esac
    IFS=',' read -ra ids <<< "$ids_string"
    for id in "${ids[@]}"; do
        id="$(echo "$id" | xargs)" # trim spazi
        [[ -z "$id" ]] && continue
        target_array+=("https://civitai.red/api/download/models/${id}")
    done
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

function provisioning_get_models() {
    local dir="$1"
    shift
    mkdir -p "$dir"
    for url in "$@"; do
        [[ -z "$url" ]] && continue
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

# --- 1. Clone o aggiornamento di ComfyUI ---
mkdir -p "${WORKSPACE}"
cd "${WORKSPACE}"

if [[ ! -d "${COMFYUI_DIR}" ]]; then
    printf "Clono ComfyUI (Comfy-Org/ComfyUI, ref: %s)...\n" "${COMFYUI_REF}"
    git clone https://github.com/Comfy-Org/ComfyUI.git
    cd "${COMFYUI_DIR}"
    git checkout "${COMFYUI_REF}"
    pip install --no-cache-dir -r requirements.txt
    pip install --no-cache-dir -r manager_requirements.txt
else
    printf "Aggiorno ComfyUI a ref: %s...\n" "${COMFYUI_REF}"
    cd "${COMFYUI_DIR}"
    git fetch --all
    git checkout "${COMFYUI_REF}"
    git pull origin "${COMFYUI_REF}" 2>/dev/null || true
    pip install --no-cache-dir -r requirements.txt
    pip install --no-cache-dir -r manager_requirements.txt
fi

# --- 2. Download modelli (fissi + quelli passati via env var RunPod) ---
provisioning_add_ids_to_array CHECKPOINT_MODELS "${CHECKPOINT_IDS_TO_DOWNLOAD}"
provisioning_add_ids_to_array LORA_MODELS "${LORAS_IDS_TO_DOWNLOAD}"

provisioning_get_models "${COMFYUI_DIR}/models/checkpoints" "${CHECKPOINT_MODELS[@]}"
provisioning_get_models "${COMFYUI_DIR}/models/loras" "${LORA_MODELS[@]}"

# --- 3. Avvio ComfyUI con Manager integrato ---
cd "${COMFYUI_DIR}"
printf "\nAvvio ComfyUI...\n\n"
python main.py --listen 0.0.0.0 --port 8188 --enable-manager
