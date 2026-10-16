#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Configure le dépôt GitHub pour le workflow d'équipe.
# À lancer par un administrateur du dépôt. Idempotent : on peut le relancer,
# il ne modifie que ce qui diffère de la configuration attendue.
#
# Étapes :
#   1. fusion des PR : squash et merge commit autorisés, rebase désactivé,
#      auto-merge, titre du commit = titre de la PR ;
#   2. GITHUB_TOKEN en lecture seule par défaut ;
#   3. branches dev et staging créées depuis main (option --create-branches) ;
#   4. environnements GitHub dev, staging et prod, chacun limité à sa branche ;
#   5. GitHub Pages publié par GitHub Actions ;
#   6. rulesets de protection des branches (.github/rulesets/*.json) ;
#   7. labels utilisés par Dependabot et les formulaires d'issue ;
#   8. contrôle des secrets attendus (noms seulement, jamais les valeurs).
#
# Prérequis : gh (authentifié avec un compte admin du dépôt) et jq.
#
# Usage : scripts/setup_github.sh [options]
#   --repo OWNER/NOM       dépôt visé (défaut : remote origin, sinon gh repo view)
#   --dry-run              affiche les modifications sans les faire (lectures seules)
#   --create-branches      crée dev et staging depuis main si elles n'existent pas
#                          (exécutez d'abord la section 1 de snowflake/04_ci_cd.sql :
#                          leur premier déploiement crée des schémas)
#   --prod-reviewer LOGIN  approbation de LOGIN exigée avant chaque déploiement prod
#                          (y compris le run planifié quotidien)
#   --skip-rulesets        ne crée ni ne met à jour les rulesets
#   -h, --help             affiche cette aide
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULESETS_DIR="${ROOT}/.github/rulesets"
DOCS_URL="https://abrahamkoloboe27.github.io/FinetrackProject-Snowflake"

DRY_RUN=false
CREATE_BRANCHES=false
SKIP_RULESETS=false
PROD_REVIEWER=""
REPO=""

# Environnements GitHub, et branche autorisée à déployer dans chacun.
ENVIRONMENTS=(dev staging prod)
env_branch() {
    case "$1" in
        prod) echo main ;;
        *) echo "$1" ;;
    esac
}

# Affiche l'en-tête du script (entre les deux lignes de tirets).
usage() {
    awk 'NR > 2 && /^# ---/ { exit } NR > 2 { sub(/^# ?/, ""); print }' "$0"
}

log() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    ATTENTION : %s\n' "$*" >&2; }
die() {
    printf 'ERREUR : %s\n' "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --repo)
            [[ $# -ge 2 ]] || die "--repo attend OWNER/NOM."
            REPO="$2"
            shift 2
            ;;
        --dry-run) DRY_RUN=true; shift ;;
        --create-branches) CREATE_BRANCHES=true; shift ;;
        --skip-rulesets) SKIP_RULESETS=true; shift ;;
        --prod-reviewer)
            [[ $# -ge 2 ]] || die "--prod-reviewer attend un login GitHub."
            PROD_REVIEWER="$2"
            shift 2
            ;;
        -h | --help) usage; exit 0 ;;
        *) die "option inconnue : $1 (voir --help)" ;;
    esac
done

# ---------------------------------------------------------------------------
# Accès à l'API. Les lectures (GET) sont toujours faites ; les écritures
# passent toutes par api_write, qui ne fait qu'afficher en --dry-run.
# ---------------------------------------------------------------------------

# Lecture JSON (GET explicite).
api_get() {
    gh api --method GET "$@"
}

# Existence d'une ressource : 0 si elle existe, 1 si 404, arrêt sinon.
api_exists() {
    local err
    if err="$(gh api --method GET "$1" --silent 2>&1)"; then
        return 0
    fi
    if [[ "$err" == *"HTTP 404"* ]]; then
        return 1
    fi
    die "lecture de $1 impossible : ${err}"
}

# Écriture : api_write MÉTHODE CHEMIN [CORPS_JSON]
api_write() {
    local method="$1" path="$2" body="${3:-}"
    if $DRY_RUN; then
        local preview=""
        if [[ -n "$body" ]]; then
            preview="$(jq -c . <<< "$body")"
            ((${#preview} > 200)) && preview="${preview:0:200}…"
        fi
        info "[dry-run] ${method} ${path} ${preview}"
        return 0
    fi
    if [[ -n "$body" ]]; then
        gh api --method "$method" "$path" --input - <<< "$body" > /dev/null
    else
        gh api --method "$method" "$path" > /dev/null
    fi
    info "${method} ${path} : fait."
}

# Clés de DESIRED (objet JSON) dont la valeur diffère dans CURRENT.
diff_keys() {
    jq -rn --argjson c "$1" --argjson d "$2" \
        '[$d | to_entries[] | select($c[.key] != .value) | .key] | join(", ")'
}

# ---------------------------------------------------------------------------
# 0. Prérequis
# ---------------------------------------------------------------------------
command -v gh > /dev/null || die "gh (GitHub CLI) est introuvable : https://cli.github.com"
command -v jq > /dev/null || die "jq est introuvable."
gh auth status > /dev/null 2>&1 || die "gh n'est pas authentifié : lancez « gh auth login »."

if [[ -z "$REPO" ]]; then
    origin="$(git -C "$ROOT" remote get-url origin 2> /dev/null || true)"
    if [[ "$origin" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
        REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
    else
        REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
    fi
fi
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "dépôt invalide : « ${REPO} » (attendu : OWNER/NOM)."

repo_json="$(api_get "repos/${REPO}")"
if [[ "$(jq -r '.permissions.admin // false' <<< "$repo_json")" != "true" ]]; then
    if $DRY_RUN; then
        warn "votre compte n'est pas admin de ${REPO} : les écritures échoueraient."
    else
        die "votre compte doit être admin de ${REPO}."
    fi
fi
DEFAULT_BRANCH="$(jq -r .default_branch <<< "$repo_json")"

echo "Dépôt : ${REPO} (branche par défaut : ${DEFAULT_BRANCH})"
$DRY_RUN && echo "Mode --dry-run : aucune modification, seules des lectures sont faites."

# ---------------------------------------------------------------------------
# 1. Réglages de fusion
# ---------------------------------------------------------------------------
log "1. Réglages de fusion des pull requests"
# delete_branch_on_merge reste à false : la suppression automatique pourrait
# toucher dev ou staging lors d'une PR de promotion. Les branches de travail
# se suppriment avec le bouton « Delete branch » après la fusion.
desired_repo='{
  "allow_squash_merge": true,
  "allow_merge_commit": true,
  "allow_rebase_merge": false,
  "allow_auto_merge": true,
  "allow_update_branch": true,
  "delete_branch_on_merge": false,
  "squash_merge_commit_title": "PR_TITLE",
  "squash_merge_commit_message": "PR_BODY",
  "merge_commit_title": "PR_TITLE",
  "merge_commit_message": "PR_BODY"
}'
changed="$(diff_keys "$repo_json" "$desired_repo")"
if [[ -z "$changed" ]]; then
    info "déjà conforme."
else
    info "à modifier : ${changed}"
    api_write PATCH "repos/${REPO}" "$desired_repo"
fi

# ---------------------------------------------------------------------------
# 2. Permissions par défaut du GITHUB_TOKEN
# ---------------------------------------------------------------------------
log "2. Permissions par défaut du GITHUB_TOKEN"
desired_perms='{"default_workflow_permissions": "read", "can_approve_pull_request_reviews": false}'
current_perms="$(api_get "repos/${REPO}/actions/permissions/workflow")"
changed="$(diff_keys "$current_perms" "$desired_perms")"
if [[ -z "$changed" ]]; then
    info "déjà conforme (lecture seule, pas d'approbation de PR par les workflows)."
else
    info "à modifier : ${changed}"
    api_write PUT "repos/${REPO}/actions/permissions/workflow" "$desired_perms"
fi

# ---------------------------------------------------------------------------
# 3. Branches longues
# ---------------------------------------------------------------------------
log "3. Branches dev et staging"
main_sha=""
for branch in staging dev; do
    if api_exists "repos/${REPO}/branches/${branch}"; then
        info "${branch} : existe."
    elif $CREATE_BRANCHES; then
        if [[ -z "$main_sha" ]]; then
            main_sha="$(api_get "repos/${REPO}/git/ref/heads/main" --jq .object.sha)"
        fi
        info "${branch} : absente, création depuis main (${main_sha:0:7})."
        api_write POST "repos/${REPO}/git/refs" \
            "$(jq -n --arg ref "refs/heads/${branch}" --arg sha "$main_sha" '{ref: $ref, sha: $sha}')"
    else
        warn "${branch} n'existe pas. Relancez avec --create-branches, ou créez-la depuis main."
    fi
done

# ---------------------------------------------------------------------------
# 4. Environnements de déploiement
# ---------------------------------------------------------------------------
log "4. Environnements dev, staging et prod"
reviewer_id=""
if [[ -n "$PROD_REVIEWER" ]]; then
    reviewer_id="$(api_get "users/${PROD_REVIEWER}" --jq .id)" \
        || die "utilisateur GitHub « ${PROD_REVIEWER} » introuvable."
    info "approbation exigée pour prod : ${PROD_REVIEWER} (id ${reviewer_id})."
    info "le run planifié quotidien attendra aussi cette approbation."
fi

for env in "${ENVIRONMENTS[@]}"; do
    branch="$(env_branch "$env")"
    body='{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}'
    if [[ "$env" == "prod" && -n "$reviewer_id" ]]; then
        # prevent_self_review à false : un mainteneur seul doit pouvoir approuver.
        body="$(jq --argjson id "$reviewer_id" \
            '. + {reviewers: [{type: "User", id: $id}], prevent_self_review: false}' <<< "$body")"
    fi

    env_exists=false
    custom=false
    if api_exists "repos/${REPO}/environments/${env}"; then
        env_exists=true
        current_env="$(api_get "repos/${REPO}/environments/${env}")"
        custom="$(jq -r '.deployment_branch_policy.custom_branch_policies // false' <<< "$current_env")"
        has_reviewer=true
        if [[ "$env" == "prod" && -n "$reviewer_id" ]]; then
            has_reviewer="$(jq --argjson id "$reviewer_id" \
                '[.protection_rules[]? | select(.type == "required_reviewers") | .reviewers[]?.reviewer.id] | index($id) != null' \
                <<< "$current_env")"
        fi
        if [[ "$custom" == "true" && "$has_reviewer" == "true" ]]; then
            info "${env} : existe, déjà conforme."
        else
            info "${env} : existe, mise à jour."
            api_write PUT "repos/${REPO}/environments/${env}" "$body"
        fi
    else
        info "${env} : absent, création."
        api_write PUT "repos/${REPO}/environments/${env}" "$body"
    fi

    # Politique de branche : seule ${branch} peut déployer dans ${env}.
    # La liste n'est lisible que si l'environnement existe avec une
    # politique personnalisée (toujours le cas après l'écriture ci-dessus).
    policies=""
    if ! $DRY_RUN || [[ "$env_exists" == "true" && "$custom" == "true" ]]; then
        policies="$(api_get "repos/${REPO}/environments/${env}/deployment-branch-policies" \
            --jq '.branch_policies[] | "\(.type // "branch"):\(.name)"')"
    fi
    if grep -qx "branch:${branch}" <<< "$policies"; then
        info "${env} : branche autorisée ${branch}, déjà en place."
    else
        api_write POST "repos/${REPO}/environments/${env}/deployment-branch-policies" \
            "$(jq -n --arg name "$branch" '{name: $name, type: "branch"}')"
    fi
    others="$(grep -vx "branch:${branch}" <<< "$policies" | grep -v '^$' || true)"
    if [[ -n "$others" ]]; then
        warn "${env} autorise aussi : $(tr '\n' ' ' <<< "$others")(à retirer à la main si inutile)."
    fi
done

# ---------------------------------------------------------------------------
# 5. GitHub Pages
# ---------------------------------------------------------------------------
log "5. GitHub Pages (source : GitHub Actions)"
if api_exists "repos/${REPO}/pages"; then
    build_type="$(api_get "repos/${REPO}/pages" --jq '.build_type // ""')"
    if [[ "$build_type" == "workflow" ]]; then
        info "déjà publié par GitHub Actions."
    else
        info "source actuelle « ${build_type} » : passage à GitHub Actions."
        api_write PUT "repos/${REPO}/pages" '{"build_type": "workflow"}'
    fi
else
    info "Pages non activé : activation."
    api_write POST "repos/${REPO}/pages" '{"build_type": "workflow"}'
fi

# ---------------------------------------------------------------------------
# 6. Rulesets
# ---------------------------------------------------------------------------
log "6. Rulesets de protection des branches"
if $SKIP_RULESETS; then
    info "ignoré (--skip-rulesets)."
else
    shopt -s nullglob
    files=("${RULESETS_DIR}"/*.json)
    shopt -u nullglob
    ((${#files[@]} > 0)) || die "aucun fichier dans ${RULESETS_DIR}."
    existing="$(api_get "repos/${REPO}/rulesets?per_page=100" \
        --jq '.[] | select(.source_type == "Repository") | "\(.id)\t\(.name)"')"
    for file in "${files[@]}"; do
        jq -e '.name and .rules' "$file" > /dev/null || die "${file} n'est pas un ruleset valide."
        name="$(jq -r .name "$file")"
        id="$(awk -F '\t' -v n="$name" '$2 == n { print $1; exit }' <<< "$existing")"
        if [[ -n "$id" ]]; then
            info "« ${name} » (${file##*/}) : mise à jour du ruleset ${id}."
            api_write PUT "repos/${REPO}/rulesets/${id}" "$(cat "$file")"
        else
            info "« ${name} » (${file##*/}) : création."
            api_write POST "repos/${REPO}/rulesets" "$(cat "$file")"
        fi
    done
    info "status checks exigés : Lint, dbt parse, Docs build, dbt build (CI), PR policy."
fi

# ---------------------------------------------------------------------------
# 7. Labels
# ---------------------------------------------------------------------------
log "7. Labels"
ensure_label() {
    local name="$1" color="$2" description="$3"
    if api_exists "repos/${REPO}/labels/${name}"; then
        info "${name} : existe."
    else
        api_write POST "repos/${REPO}/labels" \
            "$(jq -n --arg n "$name" --arg c "$color" --arg d "$description" \
                '{name: $n, color: $c, description: $d}')"
    fi
}
ensure_label dependencies 0366d6 "Mise à jour de dépendances (Dependabot)"
ensure_label bug d73a4a "Anomalie : modèle, test ou donnée incorrecte"
ensure_label enhancement a2eeef "Nouveau modèle ou évolution"

# ---------------------------------------------------------------------------
# 8. Secrets attendus (noms seulement)
# ---------------------------------------------------------------------------
log "8. Secrets Actions du dépôt (noms seulement)"
secrets="$(api_get "repos/${REPO}/actions/secrets?per_page=100" --jq '.secrets[].name')"
has_secret() { grep -qx "$1" <<< "$secrets"; }
for name in SNOWFLAKE_ACCOUNT SNOWFLAKE_USER; do
    if has_secret "$name"; then info "${name} : présent."; else warn "${name} : manquant (obligatoire)."; fi
done
if has_secret SNOWFLAKE_PRIVATE_KEY; then
    info "SNOWFLAKE_PRIVATE_KEY : présent (authentification par paire de clés)."
elif has_secret SNOWFLAKE_PASSWORD; then
    info "SNOWFLAKE_PASSWORD : présent (mot de passe ; la paire de clés est recommandée)."
else
    warn "ni SNOWFLAKE_PRIVATE_KEY ni SNOWFLAKE_PASSWORD : les jobs Snowflake échoueront."
fi
for name in SNOWFLAKE_PRIVATE_KEY_PASSPHRASE SNOWFLAKE_ROLE SNOWFLAKE_WAREHOUSE SNOWFLAKE_DATABASE; do
    has_secret "$name" && info "${name} : présent (optionnel)."
done
info "Procédure : ${DOCS_URL}/secrets/"

# ---------------------------------------------------------------------------
log "Terminé."
if $DRY_RUN; then
    echo "Aucune modification faite (--dry-run). Relancez sans --dry-run pour appliquer."
fi
cat << EOF

Étapes suivantes :
  1. Ajouter les secrets manquants : Settings → Secrets and variables → Actions.
  2. snowflake/04_ci_cd.sql, section 1 (GRANT CREATE SCHEMA) : à faire AVANT
     --create-branches. Sinon, faites-le, puis relancez les déploiements :
       gh workflow run cd.yml --ref dev
       gh workflow run cd.yml --ref staging
     Sections 2 et 3 (FINTRACK_CI_USER) : paire de clés seulement.
  3. Pages vient d'être activé : publier le site.
       gh workflow run docs.yml --ref main
  4. Ouvrir une PR de test vers dev et vérifier les 5 status checks.
Documentation : ${DOCS_URL}/ci-cd/#mise-en-place-initiale
EOF
