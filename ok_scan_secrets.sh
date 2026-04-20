#!/bin/bash

# Script de détection de secrets dans les branches Git
# Date: $(date)

set -euo pipefail

BRANCH_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --report|-r)
            REPORT_FILE="$2"; shift 2;;
        --path)
            shift 2;;
        --*)
            echo "Unknown option $1" >&2; shift;;
        *)
            BRANCH_ARG="$1"; shift;;
    esac
done

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [ -n "${BRANCH_ARG:-}" ]; then
    CURRENT_BRANCH="$BRANCH_ARG"
else
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "local")
fi

if [ -z "${REPORT_FILE:-}" ]; then
    BRANCH_SLUG=$(printf '%s' "$CURRENT_BRANCH" | sed -E 's/[^A-Za-z0-9._-]/-/g')
    REPORT_FILE="secrets_scan_report_${BRANCH_SLUG}_$(date +%Y%m%d_%H%M%S).txt"
fi

# Patterns de recherche pour les secrets
declare -a PATTERNS=(
    "password[[:space:]]*[=:][[:space:]]*['\"]?[^'\"[:space:]]{3,}['\"]?"
    "pwd[[:space:]]*[=:][[:space:]]*['\"]?[^'\"[:space:]]{3,}['\"]?"
    "secret[[:space:]]*[=:][[:space:]]*['\"]?[^'\"[:space:]]{8,}['\"]?"
    "token[[:space:]]*[=:][[:space:]]*['\"]?[^'\"[:space:]]{10,}['\"]?"
    "api_key[[:space:]]*[=:][[:space:]]*['\"]?[^'\"[:space:]]{10,}['\"]?"
    "apikey[[:space:]]*[=:][[:space:]]*['\"]?[^'\"[:space:]]{10,}['\"]?"
    "access_key[[:space:]]*[=:][[:space:]]*[^'\"[:space:]]{10,}"
    "private_key[[:space:]]*[=:][[:space:]]*['\"]?[^'\"[:space:]]{20,}['\"]?"
    "database_password[[:space:]]*[=:][[:space:]]*['\"]?[^'\"[:space:]]{3,}['\"]?"
    "db_password[[:space:]]*[=:][[:space:]]*['\"]?[^'\"[:space:]]{3,}['\"]?"
    "jdbc.*password[[:space:]]*[=:][[:space:]]*['\"]?[^'\"[:space:]]{3,}['\"]?"
    "-----BEGIN.*PRIVATE KEY-----"
    "-----BEGIN RSA PRIVATE KEY-----"
    "ssh-rsa[[:space:]]+[A-Za-z0-9+/]{100,}"
    "ssh-ed25519[[:space:]]+[A-Za-z0-9+/]{43}"
)

# Extensions de fichiers à analyser
declare -a FILE_EXTENSIONS=(
    "*.properties"
    "*.yml"
    "*.yaml"
    "*.json"
    "*.xml"
    "*.config"
    "*.conf"
    "*.env"
    "*.sh"
    "*.bash"
    "*.py"
    "*.java"
    "*.js"
    "*.ts"
    "*.php"
    "*.rb"
    "*.go"
    "*.sql"
    "*.txt"
    "*.md"
    "*.dockerfile"
    "Dockerfile*"
    "*.pem"
    "*.key"
)

# Fichiers/dossiers à exclure
declare -a EXCLUDE_PATTERNS=(
    "*.git/*"
    "*/node_modules/*"
    "*/target/*"
    "*/build/*"
    "*/dist/*"
    "*.class"
    "*.jar"
    "*.war"
    "*.ear"
    "*.zip"
    "*.tar.gz"
    "*.log"
)

echo -e "${BLUE}=== Scan de sécurité des branches Git ===${NC}"
echo "Rapport généré dans: $REPORT_FILE"
echo ""

# Initialisation du rapport
cat > "$REPORT_FILE" << EOF
=== RAPPORT DE SCAN DE SECRETS ===
Date: $(date)
Dépôt: $(git remote get-url origin 2>/dev/null || echo "Local")
Branche courante: $CURRENT_BRANCH

EOF

# Fonction pour scanner une branche
scan_branch() {
    local branch=$1
    local branch_name=$(echo "$branch" | sed 's|remotes/origin/||')
    local secrets_found=0

    echo -e "${YELLOW}Analyse de la branche: $branch_name${NC}"
    echo "=== BRANCHE: $branch_name ===" >> "$REPORT_FILE"

    # Construction de la commande find avec exclusions
    local find_cmd="find . -type f"

    # Ajout des extensions
    local ext_pattern=""
    for ext in "${FILE_EXTENSIONS[@]}"; do
        if [ -z "$ext_pattern" ]; then
            ext_pattern="-name \"$ext\""
        else
            ext_pattern="$ext_pattern -o -name \"$ext\""
        fi
    done

    # Ajout des exclusions
    for exclude in "${EXCLUDE_PATTERNS[@]}"; do
        find_cmd="$find_cmd ! -path \"$exclude\""
    done

    find_cmd="$find_cmd \( $ext_pattern \)"

    # Exécution de la recherche
    while IFS= read -r -d '' file; do
        if [ -f "$file" ] && [ -r "$file" ]; then
            if grep -qI -E "(^sops:|ENC\[)" "$file" 2>/dev/null; then
                continue
            fi
            # Vérification de chaque pattern
            for pattern in "${PATTERNS[@]}"; do
                local matches
                matches=$(grep -iHn -E "$pattern" "$file" 2>/dev/null || true)
                if [ -n "$matches" ]; then
                    echo -e "${RED}  ⚠️  Secret potentiel trouvé dans: $file${NC}"
                    echo "FICHIER: $file" >> "$REPORT_FILE"
                    while IFS= read -r mline; do
                        echo "$mline" >> "$REPORT_FILE"
                    done <<< "$matches"
                    echo "" >> "$REPORT_FILE"
                    ((secrets_found++))
                fi
            done
        fi
    done < <(eval "$find_cmd -print0" 2>/dev/null)

    if [ $secrets_found -eq 0 ]; then
        echo -e "${GREEN}  ✅ Aucun secret détecté${NC}"
        echo "Aucun secret détecté" >> "$REPORT_FILE"
    else
        echo -e "${RED}  ⚠️  $secrets_found secret(s) potentiel(s) trouvé(s)${NC}"
        echo "TOTAL: $secrets_found secret(s) potentiel(s) trouvé(s)" >> "$REPORT_FILE"
    fi

    echo "" >> "$REPORT_FILE"
    echo "---" >> "$REPORT_FILE"
    echo ""

    return $secrets_found
}

echo "Branche analysée: $CURRENT_BRANCH"

total_secrets=0

# Scan the current branch (no loop needed)
scan_branch "$CURRENT_BRANCH"
rc=$?
if [ $rc -gt 0 ]; then
    total_secrets=$rc
fi

echo -e "${BLUE}Scan effectué sur la branche actuelle: $CURRENT_BRANCH${NC}"

# Résumé final
echo -e "${BLUE}=== RÉSUMÉ DU SCAN ===${NC}"
if [ $total_secrets -eq 0 ]; then
    echo -e "${GREEN}✅ Aucun secret détecté dans toutes les branches analysées${NC}"
else
    echo -e "${RED}⚠️  TOTAL: $total_secrets secret(s) potentiel(s) trouvé(s) dans toutes les branches${NC}"
    echo -e "${YELLOW}📄 Consultez le rapport détaillé: $REPORT_FILE${NC}"
fi

# Ajout du résumé au rapport
cat >> "$REPORT_FILE" << EOF

=== RÉSUMÉ FINAL ===
Total de secrets potentiels trouvés: $total_secrets
Branche analysée: $CURRENT_BRANCH
Date de fin: $(date)
EOF

echo ""
echo -e "${BLUE}Scan terminé. Rapport sauvegardé dans: $REPORT_FILE${NC}"

# Exit with non-zero if any secrets found (standard CI behavior)
if [ $total_secrets -gt 0 ]; then
    exit 1
fi
exit 0
