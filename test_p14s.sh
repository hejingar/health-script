#!/bin/bash

# ============================================
# Script de test P14s Gen 2 AMD
# ============================================
# Usage: sudo bash test_p14s.sh
# ============================================

set -e

echo "=========================================="
echo "  TEST P14s Gen 2 AMD - $(date)"
echo "=========================================="
echo ""

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================
# 1. INSTALLATION DES PACKAGES
# ============================================
echo "[1/9] Installation des packages necessaires..."

PACKAGES="stress-ng smartmontools lm-sensors upower"

for pkg in $PACKAGES; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        echo "  -> Installation de $pkg..."
        apt-get update -qq && apt-get install -y -qq $pkg >/dev/null 2>&1
    else
        echo "  -> $pkg deja installe"
    fi
done

echo ""

# ============================================
# 2. BATTERIE
# ============================================
echo "[2/9] Test batterie..."

if command -v upower >/dev/null 2>&1; then
    BATTERY_PATH=$(upower -e | grep -i battery | head -n 1)
    if [ -n "$BATTERY_PATH" ]; then
        upower -i $BATTERY_PATH > /tmp/battery_info.txt
        CAPACITY=$(grep "percentage:" /tmp/battery_info.txt | awk '{print $2}' | tr -d '%')
        ENERGY_FULL=$(grep "energy-full:" /tmp/battery_info.txt | awk '{print $2}' | tr -d 'Wh')
        ENERGY_DESIGN=$(grep "energy-full-design:" /tmp/battery_info.txt | awk '{print $2}' | tr -d 'Wh')

        echo "  Capacite actuelle: ${CAPACITY}%"
        echo "  Energie actuelle: ${ENERGY_FULL} Wh"
        echo "  Energie design: ${ENERGY_DESIGN} Wh"

        if [ "$CAPACITY" -ge 80 ]; then
            echo -e "  ${GREEN}✓ Batterie en bon etat${NC}"
        elif [ "$CAPACITY" -ge 60 ]; then
            echo -e "  ${YELLOW}⚠ Batterie moyenne${NC}"
        else
            echo -e "  ${RED}✗ Batterie faible - a remplacer${NC}"
        fi
    else
        echo "  Batterie non detectee"
    fi
else
    echo "  upower non disponible"
fi

echo ""

# ============================================
# 3. SSD / NVMe
# ============================================
echo "[3/9] Test SSD..."

# Detection du disque
DISK=$(lsblk -d -o NAME,TYPE | grep nvme | awk '{print $1}' | head -n 1)
if [ -z "$DISK" ]; then
    DISK=$(lsblk -d -o NAME,TYPE | grep -E "sd[a-z]" | grep -v "^sda" | awk '{print $1}' | head -n 1)
fi

if [ -n "$DISK" ]; then
    echo "  Disque detecte: /dev/$DISK"

    if command -v smartctl >/dev/null 2>&1; then
        smartctl -a /dev/$DISK > /tmp/smart_info.txt 2>/dev/null || true

        # Pourcentage d'usure
        PERCENT_USED=$(grep "Percentage Used" /tmp/smart_info.txt | awk '{print $3}' | tr -d '%' || echo "N/A")
        if [ "$PERCENT_USED" != "N/A" ] && [ -n "$PERCENT_USED" ]; then
            echo "  Usure SSD: ${PERCENT_USED}%"
            if [ "$PERCENT_USED" -le 10 ]; then
                echo -e "  ${GREEN}✓ SSD quasi neuf${NC}"
            elif [ "$PERCENT_USED" -le 30 ]; then
                echo -e "  ${YELLOW}⚠ SSD usage modere${NC}"
            else
                echo -e "  ${RED}✗ SSD bien use${NC}"
            fi
        else
            echo "  Info d'usure non disponible (peut-etre SATA)"
        fi

        # Taille
        SIZE=$(lsblk -d -o SIZE /dev/$DISK | tail -n 1)
        echo "  Taille: $SIZE"
    else
        echo "  smartctl non disponible"
    fi
else
    echo "  Disque non detecte"
fi

echo ""

# ============================================
# 4. CPU & RAM
# ============================================
echo "[4/9] Info CPU & RAM..."

echo "  CPU: $(grep 'model name' /proc/cpuinfo | head -n 1 | cut -d':' -f2 | xargs)"
echo "  Nombre de coeurs: $(nproc)"
echo "  RAM totale: $(free -h | grep Mem | awk '{print $2}')"
echo "  RAM disponible: $(free -h | grep Mem | awk '{print $7}')"

echo ""

# ============================================
# 5. STRESS TEST CPU (5 minutes)
# ============================================
echo "[5/9] Stress test CPU (5 minutes)..."
echo "  Lancement de stress-ng --cpu 8 --timeout 300s"
echo "  Ne ferme pas ce terminal !"
echo ""

if command -v stress-ng >/dev/null 2>&1; then
    stress-ng --cpu 8 --timeout 300s --metrics-brief 2>&1 | tee /tmp/stress_result.txt

    if grep -q "successful run completed" /tmp/stress_result.txt; then
        echo -e "  ${GREEN}✓ Stress test passe avec succes${NC}"
    else
        echo -e "  ${RED}✗ Probleme detecte pendant le stress test${NC}"
    fi
else
    echo "  stress-ng non disponible"
fi

echo ""

# ============================================
# 6. TEMPERATURES
# ============================================
echo "[6/9] Temperatures..."

if command -v sensors >/dev/null 2>&1; then
    sensors > /tmp/sensors_info.txt 2>/dev/null || true

    # Extraction de la temp CPU
    CPU_TEMP=$(grep -E "Tctl|Core 0|Package id 0" /tmp/sensors_info.txt | head -n 1 | awk '{print $2}' | tr -d '+°C' || echo "N/A")

    if [ "$CPU_TEMP" != "N/A" ] && [ -n "$CPU_TEMP" ]; then
        echo "  Temperature CPU: ${CPU_TEMP}°C"

        if [ "$CPU_TEMP" -le 70 ]; then
            echo -e "  ${GREEN}✓ Temperature normale${NC}"
        elif [ "$CPU_TEMP" -le 85 ]; then
            echo -e "  ${YELLOW}⚠ Temperature elevee${NC}"
        else
            echo -e "  ${RED}✗ Temperature critique${NC}"
        fi
    else
        echo "  Temperature non disponible"
        cat /tmp/sensors_info.txt
    fi
else
    echo "  lm-sensors non disponible"
fi

echo ""

# ============================================
# 7. ECRAN
# ============================================
echo "[7/9] Info ecran..."

# Resolution
RESOLUTION=$(xrandr 2>/dev/null | grep '*' | awk '{print $1}' | head -n 1 || echo "N/A")
echo "  Resolution: $RESOLUTION"

# Detection du modele d'ecran
if [ -d /sys/class/drm/ ]; then
    for card in /sys/class/drm/card*-eDP-1; do
        if [ -f "$card/status" ]; then
            STATUS=$(cat "$card/status" 2>/dev/null || echo "N/A")
            if [ "$STATUS" = "connected" ]; then
                echo "  Ecran connecte: $card"
                break
            fi
        fi
    done
fi

echo "  (Verifie visuellement: dead pixels, backlight bleed, angles de vue)"

echo ""

# ============================================
# 8. PERIPHERIQUES
# ============================================
echo "[8/9] Peripheriques detectes..."

# USB
echo "  Ports USB:"
lsusb 2>/dev/null | head -n 5 || echo "    lsusb non disponible"

# Audio
echo "  Cartes audio:"
aplay -l 2>/dev/null | head -n 3 || echo "    aplay non disponible"

# Webcam
echo "  Webcams:"
ls /dev/video* 2>/dev/null || echo "    Aucune webcam detectee"

# Bluetooth
echo "  Bluetooth:"
if [ -d /sys/class/bluetooth/ ]; then
    echo "    Present"
else
    echo "    Non detecte"
fi

echo ""

# ============================================
# 9. RESUME
# ============================================
echo "=========================================="
echo "  RESUME DES TESTS"
echo "=========================================="
echo ""

echo "Fichiers de log crees:"
echo "  - /tmp/battery_info.txt"
echo "  - /tmp/smart_info.txt"
echo "  - /tmp/stress_result.txt"
echo "  - /tmp/sensors_info.txt"
echo ""

echo "Verifications manuelles a faire:"
echo "  ☐ Clavier: toutes les touches, touche manquante, retroeclairage"
echo "  ☐ TrackPoint: rouge, clic gauche/droit/milieu"
echo "  ☐ Ports: USB-A, USB-C charge, HDMI, RJ45, jack"
echo "  ☐ Charnieres: ouverture/fermeture, pas de grincement"
echo "  ☐ Chassis: flex, coins, palmrest"
echo "  ☐ Ecran: fond blanc (dead pixels), fond noir (backlight bleed)"
echo ""

echo "=========================================="
echo "  Script termine - $(date)"
echo "=========================================="
