#!/bin/bash

# ============================
# Monitor de recursos del sistema
# ============================

# --- Cargar variables de entorno ---
cargar_env() {
    local ENV_FILE=".env"
    if [ ! -f "$ENV_FILE" ]; then
        echo "⚠️ No se encontró $ENV_FILE"
        return 1
    fi
    while IFS='=' read -r clave valor || [ -n "$clave" ]; do
        [[ "$clave" =~ ^[[:space:]]*# || -z "$clave" ]] && continue
        valor="${valor%\"}"; valor="${valor#\"}"
        valor="${valor%\'}"; valor="${valor#\'}"
        export "$clave=$valor"
    done < "$ENV_FILE"
    return 0
}

# --- Utilidades ---
log() {
    local FECHA_HORA=$(date '+%Y-%m-%d %H:%M:%S')
    local LOG_HOY="${LOG_BASE}_$(date '+%Y-%m-%d').log"
    echo "[${FECHA_HORA}] $1" | tee -a "$LOG_HOY"
}

rotar_logs() {
    find "$(dirname "$LOG_BASE")" -name "$(basename "$LOG_BASE")_*.log" \
        -mtime +${MAX_LOGS} -delete
    log "Rotación de logs: eliminados registros con más de ${MAX_LOGS} días."
}

# --- Telegram ---
enviar_telegram() {
    local mensaje="$1"
    if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
        return 0
    fi
    local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    curl -s --max-time 10 -X POST "$url" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "parse_mode=Markdown" \
        --data-urlencode "text=${mensaje}" >/dev/null || log "❌ Fallo enviando alerta a Telegram."
}

# --- Limpieza de logs antiguos ---
limpiar_logs() {
    find "$LOG_DIR" -maxdepth 1 -type f \
        | sed 's/\.[0-9]*$//' | sed 's/\.log.*$//' | sort -u \
        | while read -r prefijo; do
        local archivos total
        archivos=$(find "$LOG_DIR" -maxdepth 1 -type f \
            -name "$(basename "$prefijo")*" | sort -t . -k2 -r)
        total=$(echo "$archivos" | grep -c .)
        if [[ "$total" -le 1 ]]; then
            continue
        fi
        echo "$archivos" | tail -n +2 | while read -r archivo; do
            rm -f "$archivo"
            log "Eliminado: $archivo"
        done
    done
}

# --- Monitores ---
revisar_disco() {
    local USO USO_FINAL mensaje
    USO=$(df -h / | grep -v "^Filesystem" | awk '{print $5}' | sed 's/%//')
    log "💽 Disco: uso ${USO}%"
    USO_FINAL=$USO
    if [ "$USO" -gt "$UMBRAL_DISCO" ]; then
        log "⚠️ Disco supera el ${UMBRAL_DISCO}%. Iniciando limpieza..."
        limpiar_logs
        USO_FINAL=$(df -h / | grep -v "^Filesystem" | awk '{print $5}' | sed 's/%//')
        log "✅ Limpieza completada. Uso de disco: ${USO_FINAL}%"
        enviar_telegram "🚨 ALERTA DISCO en $(hostname)\nUso: ${USO_FINAL}% (umbral ${UMBRAL_DISCO}%)"
    fi
}

revisar_ram() {
    local USO=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
    log "🧠 RAM: uso ${USO}%"
    if [ "$USO" -gt "$UMBRAL_RAM" ]; then
        enviar_telegram "🚨 ALERTA RAM en $(hostname)\nUso: ${USO}% (umbral ${UMBRAL_RAM}%)"
    fi
}

revisar_cpu() {
    local USO procesos mensaje
    USO=$(top -bn1 | awk '/Cpu\(s\)/ {print 100 - $8}' | cut -d. -f1)
    log "⚙️ CPU: uso ${USO}%"
    if [ "$USO" -gt "$UMBRAL_CPU" ]; then
        procesos=$(ps -eo pid,comm,%cpu --sort=-%cpu | head -n 6)
        log "⚠️ CPU supera el ${UMBRAL_CPU}%. Top procesos por CPU:"
        echo "$procesos" | tail -n 5 | while read -r linea; do log "$linea"; done
        enviar_telegram "🚨 ALERTA CPU en $(hostname)\nUso: ${USO}% (umbral ${UMBRAL_CPU}%)\n\`\`\`\n${procesos}\n\`\`\`"
    fi
}

# --- Arranque ---
trap 'log "Monitor detenido (señal recibida). PID: $$"; exit 0' SIGINT SIGTERM

if cargar_env; then
    log "Variables cargadas desde .env"
else
    log "⚠️ No se encontró .env – las alertas de Telegram quedarán desactivadas."
fi

log "Monitor iniciado | PID: $$ | Host: $(hostname)"
log "Umbrales -> Disco:${UMBRAL_DISCO}% | RAM:${UMBRAL_RAM}% | CPU:${UMBRAL_CPU}%"
log "Intervalo: ${INTERVALO}s"

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    log "Telegram: ✅ configurado (chat ${TELEGRAM_CHAT_ID})"
else
    log "Telegram: ❌ no configurado"
fi

enviar_telegram "🟢 Monitor iniciado en $(hostname)\nVigilando disco/RAM/CPU cada ${INTERVALO}s."

ULTIMO_DIA=$(date +'%Y-%m-%d')
while true; do
    DIA_ACTUAL=$(date +'%Y-%m-%d')
    if [ "$DIA_ACTUAL" != "$ULTIMO_DIA" ]; then
        log "Nuevo día detectado. Ejecutando rotación de logs..."
        rotar_logs
        ULTIMO_DIA="$DIA_ACTUAL"
    fi
    revisar_disco
    revisar_ram
    revisar_cpu
    log "Próxima revisión en ${INTERVALO} segundos."
    sleep "$INTERVALO"
done
