#!/bin/bash
# ============================================================
# Provisioning script personalizzato - AI-Dock ComfyUI
# Workflow target: Wan 2.2 I2V (YAW_2_2_T2V_I2V_v0_39_MoE)
#
# COME USARLO:
# 1. Nel template RunPod, ogni URL_* qui sotto e' una env var separata.
#    Lascia vuota una variabile per SALTARE quel download (boot veloce).
#    Compila l'URL per scaricare quel modello specifico (fp8, fp16,
#    o qualsiasi altra variante: basta cambiare il link).
# 2. Imposta CIVITAI_TOKEN se uno o piu' URL puntano a civitai.com/.red
#    (richiesto solo per i modelli "gated"; per Hugging Face usa HF_TOKEN).
# 3. Container image consigliata: ghcr.io/ai-dock/comfyui:latest-cuda
#    Porte HTTP: 8188 (ComfyUI), 1111 (Instance Portal), 8888 (Jupyter)
#    Porta TCP: 22 (SSH)
# 4. I custom node NON sono gestiti da questo script: al primo avvio,
#    carica il workflow .json in ComfyUI e usa ComfyUI-Manager
#    ("Install Missing Custom Nodes") per installarli in modo affidabile.
#    ComfyUI-Manager stesso e' pre-installato da questo script.
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

# --- Custom node "di base" sempre installati (gestiscono il resto Manager) ---
NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
)

# ============================================================
# MODELLI - Diffusion e LoRA sono flessibili (un URL per slot, da
# impostare nel template RunPod ad ogni deploy in base a cosa vuoi
# testare: fp8/fp16, variante diversa, ecc.). VAE, CLIP e GIMMVFI
# sono invece FISSI qui sotto, perche' restano gli stessi
# indipendentemente dalla variante del modello diffusion scelta.
# ============================================================

# --- Diffusion models (UNETLoader) - Wan 2.2 I2V - FLESSIBILI ---
# Esempi:
#   fp8_scaled (~14.3GB cad.): https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors
#   fp16       (~28.6GB cad.): https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp16.safetensors
URL_I2V_HIGH_NOISE="${URL_I2V_HIGH_NOISE:-}"
URL_I2V_LOW_NOISE="${URL_I2V_LOW_NOISE:-}"

# --- LoRA - FLESSIBILE ---
URL_WAN_LORA="${URL_WAN_LORA:-}"

# --- VAE - FISSO ---
# wan_2.1_vae.safetensors (~0.25GB) - richiesto dai modelli 14B
URL_WAN_VAE="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors"

# --- Text encoder / CLIP - FISSO ---
# umt5_xxl_fp8_e4m3fn_scaled.safetensors (~6GB)
URL_WAN_CLIP="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"

# --- GIMM-VFI (frame interpolation) - FISSO ---
# gimmvfi_r_arb_lpips_fp32.safetensors (~79MB)
URL_GIMMVFI="https://huggingface.co/Kijai/GIMM-VFI_safetensors/resolve/main/gimmvfi_r_arb_lpips_fp32.safetensors"

# --- Slot generici extra, per qualsiasi altro modello/variante futura ---
# Compila url+cartella di destinazione (nome esatto da
# /opt/ai-dock/storage_monitor/etc/mappings.sh, es: unet, vae, clip, lora,
# checkpoints, controlnet, upscale_models, ecc.) se serve in futuro senza
# dover riscrivere lo script: esempio gia' pronto, lascia vuoto se non serve.
URL_EXTRA_1="${URL_EXTRA_1:-}"
URL_EXTRA_1_DEST="${URL_EXTRA_1_DEST:-unet}"
URL_EXTRA_2="${URL_EXTRA_2:-}"
URL_EXTRA_2_DEST="${URL_EXTRA_2_DEST:-unet}"

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
    provisioning_get_wan_models
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

# Scarica un singolo URL (se non vuoto) in una sottocartella di models/.
# $1 = URL (puo' essere vuoto: in tal caso non fa nulla)
# $2 = nome cartella sotto ${WORKSPACE}/storage/stable_diffusion/models/
function provisioning_get_single_model() {
    local url="$1"
    local subdir="$2"
    if [[ -z "$url" || "${url,,}" == "skip" || "$url" == *"placeholder"* ]]; then
        return 0
    fi
    local dir="${WORKSPACE}/storage/stable_diffusion/models/${subdir}"
    mkdir -p "$dir"
    printf "Downloading to %s: %s\n" "$subdir" "$url"
    provisioning_download "$url" "$dir"
    printf "\n"
}

function provisioning_get_wan_models() {
    if [[ $DISK_GB_ALLOCATED -lt $DISK_GB_REQUIRED ]]; then
        printf "WARNING: Low disk space allocation (%sGB available, %sGB required) - downloads may fail or fill the disk!\n" "$DISK_GB_ALLOCATED" "$DISK_GB_REQUIRED"
    fi
    # Nomi cartella confermati da /opt/ai-dock/storage_monitor/etc/mappings.sh:
    # unet (non "diffusion_models"), clip (non "text_encoders"), lora, vae.
    # GIMMVFI non ha un mapping dedicato: lo mettiamo comunque sotto
    # storage/ (cosi' resta sul Volume persistente) ma con un symlink
    # manuale verso /opt/ComfyUI/models/gimmvfi, dato che il watcher
    # automatico non lo gestisce.
    provisioning_get_single_model "$URL_I2V_HIGH_NOISE" "unet"
    provisioning_get_single_model "$URL_I2V_LOW_NOISE"  "unet"
    provisioning_get_single_model "$URL_WAN_VAE"         "vae"
    provisioning_get_single_model "$URL_WAN_CLIP"        "clip"
    provisioning_get_single_model "$URL_WAN_LORA"        "lora"
    provisioning_get_gimmvfi_model
    provisioning_get_single_model "$URL_EXTRA_1" "$URL_EXTRA_1_DEST"
    provisioning_get_single_model "$URL_EXTRA_2" "$URL_EXTRA_2_DEST"
}

function provisioning_get_gimmvfi_model() {
    if [[ -z "$URL_GIMMVFI" || "${URL_GIMMVFI,,}" == "skip" ]]; then
        return 0
    fi
    # Nessun mapping automatico per gimmvfi in mappings.sh: scarichiamo
    # su storage/ (persistente) e creiamo noi il symlink verso ComfyUI.
    local storage_dir="${WORKSPACE}/storage/stable_diffusion/models/gimmvfi"
    local target_dir="/opt/ComfyUI/models/gimmvfi"
    mkdir -p "$storage_dir"
    printf "Downloading to gimmvfi: %s\n" "$URL_GIMMVFI"
    provisioning_download "$URL_GIMMVFI" "$storage_dir"
    mkdir -p "$(dirname "$target_dir")"
    if [[ ! -e "$target_dir" ]]; then
        ln -s "$storage_dir" "$target_dir"
    fi
    printf "\n"
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
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
