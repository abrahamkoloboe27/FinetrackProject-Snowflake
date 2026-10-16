#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Vérifie que les secrets Snowflake sont disponibles, sans jamais afficher
# leur valeur.
#
# Variables contrôlées (passées par le workflow depuis les secrets) :
#   SNOWFLAKE_ACCOUNT                       obligatoire
#   SNOWFLAKE_USER                          obligatoire
#   SNOWFLAKE_PRIVATE_KEY ou SNOWFLAKE_PASSWORD   l'un des deux
#   SNOWFLAKE_PRIVATE_KEY_PASSPHRASE        seulement si la clé est chiffrée
#
# Modes :
#   (défaut) --strict : secret manquant → ::error:: et code de sortie 1
#            --soft   : secret manquant → ::warning:: et code de sortie 0
# Dans les deux cas, écrit ready=true|false dans $GITHUB_OUTPUT s'il existe :
# les étapes suivantes testent steps.<id>.outputs.ready (un secret ne peut
# pas être lu dans un `if:` de workflow).
#
# Usage : scripts/ci/check_snowflake_env.sh [--strict|--soft]
# ---------------------------------------------------------------------------
set -euo pipefail

DOC_URL="${DOCS_SECRETS_URL:-https://abrahamkoloboe27.github.io/FinetrackProject-Snowflake/secrets/}"

# Affiche l'en-tête du script (entre les deux lignes de tirets).
usage() {
    awk 'NR > 2 && /^# ---/ { exit } NR > 2 { sub(/^# ?/, ""); print }' "$0"
}

mode=strict
for arg in "$@"; do
    case "$arg" in
        --soft) mode=soft ;;
        --strict) mode=strict ;;
        -h | --help) usage; exit 0 ;;
        *) echo "Option inconnue : ${arg}" >&2; usage >&2; exit 2 ;;
    esac
done

# Vrai si la variable est absente, vide ou ne contient que des espaces.
is_blank() {
    local value="${!1:-}"
    [[ -z "${value//[[:space:]]/}" ]]
}

write_output() {
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "ready=$1" >> "$GITHUB_OUTPUT"
    fi
}

missing=()
problems=()

is_blank SNOWFLAKE_ACCOUNT && missing+=("SNOWFLAKE_ACCOUNT")
is_blank SNOWFLAKE_USER && missing+=("SNOWFLAKE_USER")
if is_blank SNOWFLAKE_PRIVATE_KEY && is_blank SNOWFLAKE_PASSWORD; then
    missing+=("SNOWFLAKE_PRIVATE_KEY (ou SNOWFLAKE_PASSWORD)")
fi

# Pièges de format connus de dbt-snowflake pour la clé privée. Seule la
# forme est examinée (premier caractère, en-tête PEM), jamais affichée.
if ! is_blank SNOWFLAKE_PRIVATE_KEY; then
    key="${SNOWFLAKE_PRIVATE_KEY}"
    if [[ "$key" =~ ^[[:space:]] ]]; then
        problems+=("SNOWFLAKE_PRIVATE_KEY commence par une espace ou un retour à la ligne : dbt-snowflake ne la reconnaît pas. Recollez la clé sans rien avant « -----BEGIN » (ou en base64 DER sur une ligne).")
    fi
    if [[ "$key" == *'\n'* ]]; then
        problems+=("SNOWFLAKE_PRIVATE_KEY contient des « \\n » littéraux : collez la clé PEM avec de vrais retours à la ligne, ou en base64 DER sur une ligne.")
    fi
    # En-têtes PEM construits en deux morceaux : le hook detect-private-key
    # de pre-commit ne confond pas ce script avec une vraie clé.
    pem_encrypted="BEGIN ""ENCRYPTED PRIVATE KEY"
    pem_plain="BEGIN ""PRIVATE KEY"
    if [[ "$key" == *"$pem_encrypted"* ]] && is_blank SNOWFLAKE_PRIVATE_KEY_PASSPHRASE; then
        problems+=("La clé privée est chiffrée mais SNOWFLAKE_PRIVATE_KEY_PASSPHRASE est vide.")
    fi
    if [[ "$key" == *"$pem_plain"* ]] && ! is_blank SNOWFLAKE_PRIVATE_KEY_PASSPHRASE; then
        problems+=("La clé privée n'est pas chiffrée : supprimez le secret SNOWFLAKE_PRIVATE_KEY_PASSPHRASE (dbt-snowflake refuse une phrase de passe dans ce cas).")
    fi
    unset key
    if ! is_blank SNOWFLAKE_PASSWORD; then
        echo "::notice title=Authentification Snowflake::SNOWFLAKE_PRIVATE_KEY et SNOWFLAKE_PASSWORD sont tous deux définis : la paire de clés est utilisée."
    fi
fi

if (( ${#missing[@]} == 0 && ${#problems[@]} == 0 )); then
    if is_blank SNOWFLAKE_PRIVATE_KEY; then
        auth="mot de passe"
        echo "::notice title=Authentification Snowflake::Mot de passe : accepté sur un compte d'essai uniquement. Sur un compte payant, ou si l'utilisateur est inscrit au MFA, Snowflake refuse la connexion : passez à la paire de clés (${DOC_URL})."
    else
        auth="paire de clés"
    fi
    echo "Secrets Snowflake présents (authentification par ${auth})."
    write_output true
    exit 0
fi

# Message unique : liste des secrets manquants et des problèmes de format.
details=""
if (( ${#missing[@]} > 0 )); then
    details="Secrets manquants ou vides : $(printf '%s, ' "${missing[@]}")"
    details="${details%, }."
fi
# (forme ${tableau[@]+…} : compatible avec le bash 3.2 de macOS sous set -u)
for p in ${problems[@]+"${problems[@]}"}; do
    details="${details:+${details} }${p}"
done
where="Ajoutez-les dans Settings → Secrets and variables → Actions (secrets du dépôt, ou de l'environnement GitHub du job). Procédure : ${DOC_URL}"

write_output false

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo "### Secrets Snowflake"
        echo
        for m in ${missing[@]+"${missing[@]}"}; do echo "- manquant : \`${m}\`"; done
        for p in ${problems[@]+"${problems[@]}"}; do echo "- ${p}"; done
        echo
        echo "${where}"
    } >> "$GITHUB_STEP_SUMMARY"
fi

if [[ "$mode" == "soft" ]]; then
    echo "::warning title=Secrets Snowflake::${details} Les étapes Snowflake sont ignorées. ${where}"
    exit 0
fi

echo "::error title=Secrets Snowflake::${details} ${where}"
exit 1
