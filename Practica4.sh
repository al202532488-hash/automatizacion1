#!/bin/bash

DEST_DIR="/tmp/disk_test"
TOTAL FILES=15
LOG_FILE="/tmp/sim_disk.log"

mkdir -p "$DEST_DIR"

echo "===============================" | tee -a "$LOG_FILE"
echo "Inicio de simulación: $(date)" | tee -a "$LOG_FILE"
echo "==============================" | tee -a "$LOG_FILE"

SIZES=(50 100 200 150 75 300 120 80 250 400 1024)

for i in $(seq 1 STOTAL FILES); do 
    SIZE=${SIZES[$((i-1))]}
    FILE="$DEST_DIR/testfile_${i}_${SIZE}mb.bin"

    echo "[$(date +%T)] Creando $FILE (${SIZE} MB)..." | tee -a "$LOG_FILE"

   fallocate -1 "${SIZE}M" "$FILE" 2>/dev/null || dd if=/dev/zero of="$FILE" bs=1M count="$SIZE"
   status=none
   
   echo "[$(date +%T)] Uso actual: $(df -h "DEST_DIR" | awk ' NR==2 { print $3 " usados / $2" total (" $5" usando)"}')" | tee -a "$LOG_FILE"

  sleep 2
done
    
   

