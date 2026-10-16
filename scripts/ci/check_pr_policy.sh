#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Contrôle d'une pull request : flux de branches et titre.
#
# Appelé par le workflow « PR policy » (.github/workflows/pr-policy.yml).
# Les données de la PR arrivent par des variables d'environnement, jamais
# par interpolation dans le code du workflow (elles sont saisies par
# l'auteur de la PR et ne doivent jamais être exécutées) :
#   BASE_REF   branche cible (dev, staging ou main)
#   HEAD_REF   branche source
#   PR_TITLE   titre de la PR
#   HEAD_REPO  dépôt de la branche source (owner/nom ; vide si le fork a
#              été supprimé)                                    facultatif
#   BASE_REPO  dépôt de la PR (owner/nom)                       facultatif
#
# Règles (voir docs/workflow-git.md) :
#   - base main    : head = staging ou hotfix/*
#   - base staging : head = dev, main ou hotfix/*
#   - base dev     : head = staging, main ou <type>/<sujet>
#   - PR venant d'un fork (HEAD_REPO différent de BASE_REPO) : elle vise
#     dev, et sa branche ne s'appelle ni dev, ni staging, ni main (une
#     promotion ou un back-merge vient toujours du dépôt principal) ;
#     sans BASE_REPO (usage local), ce contrôle est ignoré
#   - titre au format Conventional Commits : type(portée)!: description
#
# Sortie : 0 si la PR respecte les règles, 1 sinon (annotations ::error::).
# Usage local :
#   BASE_REF=dev HEAD_REF=feature/x PR_TITLE="feat: x" scripts/ci/check_pr_policy.sh
# ---------------------------------------------------------------------------
set -euo pipefail

# Classes de caractères et plages [a-z] interprétées octet par octet.
export LC_ALL=C

DOC_URL="${DOCS_WORKFLOW_URL:-https://abrahamkoloboe27.github.io/FinetrackProject-Snowflake/workflow-git/}"

# Préfixes autorisés pour une branche de travail qui vise dev.
WORK_PREFIXES='feature|feat|fix|hotfix|docs|chore|refactor|test|ci|perf|build|style|deps|dependabot'
# Types Conventional Commits acceptés dans le titre.
TITLE_TYPES='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|release'
TITLE_REGEX="^(${TITLE_TYPES})(\\([a-z0-9._/-]+\\))?!?: (.+)$"

base="${BASE_REF:-}"
head="${HEAD_REF:-}"
title="${PR_TITLE:-}"
head_repo="${HEAD_REPO:-}"
base_repo="${BASE_REPO:-}"

errors=0
summary_lines=()

# Échappe un message pour une commande de workflow GitHub (::error:: …).
escape_cmd() {
    local s="$1"
    s="${s//'%'/'%25'}"
    s="${s//$'\r'/'%0D'}"
    s="${s//$'\n'/'%0A'}"
    printf '%s' "$s"
}

# Annotations GitHub : erreur (bloquante), avertissement, information.
fail() {
    errors=$((errors + 1))
    echo "::error title=$1::$(escape_cmd "$2")"
    summary_lines+=("- **$1** : $2")
}

warn() {
    echo "::warning title=$1::$(escape_cmd "$2")"
    summary_lines+=("- _Avertissement_ : $2")
}

note() {
    echo "::notice title=$1::$(escape_cmd "$2")"
    summary_lines+=("- $2")
}

if [[ -z "$base" || -z "$head" ]]; then
    echo "::error title=Paramètres manquants::BASE_REF et HEAD_REF doivent être définis (voir l'en-tête du script)."
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. Flux de branches
# ---------------------------------------------------------------------------
flow_ok=false
merge_hint=""
# Une PR de fork n'est comparée qu'au nom de sa branche : un fork
# « quelquun:staging » passerait pour une promotion staging → main. Le
# build Snowflake (dbt build (CI)) est de plus ignoré pour un fork.
fork_refused=false
if [[ -n "$base_repo" && "$head_repo" != "$base_repo" ]]; then
    fork_label="${head_repo:-supprimé}"
    if [[ "$head" == "dev" || "$head" == "staging" || "$head" == "main" ]]; then
        fork_refused=true
        fail "Promotion ou back-merge refusé" \
            "Une PR depuis dev, staging ou main doit venir du dépôt principal ${base_repo}, pas du fork ${fork_label}. Renommez la branche du fork (ex. feature/<sujet>) et visez dev. Voir ${DOC_URL}"
    elif [[ "$base" != "dev" ]]; then
        fork_refused=true
        fail "Une PR venant d'un fork vise dev" \
            "La branche vient du fork ${fork_label} : visez dev (gh pr edit <n> --base dev). staging et main ne reçoivent que des promotions et des hotfix du dépôt principal. Voir ${DOC_URL}"
    fi
fi

# Fork refusé ci-dessus : inutile d'appliquer les règles par base.
if ! $fork_refused; then
    case "$base" in
        main)
            if [[ "$head" == "staging" ]]; then
                flow_ok=true
                merge_hint="Promotion staging → main : fusionner en « Create a merge commit » (pas de squash)."
            elif [[ "$head" =~ ^hotfix/.+ ]]; then
                flow_ok=true
                merge_hint="Correctif urgent : fusionner en « Squash and merge »."
            else
                fail "Flux de branches refusé" \
                    "main (production) n'accepte que staging ou une branche hotfix/<sujet>, pas « ${head} ». Visez dev pour une branche de travail : dev → staging → main. Voir ${DOC_URL}"
            fi
            ;;
        staging)
            if [[ "$head" == "dev" ]]; then
                flow_ok=true
                merge_hint="Release dev → staging : fusionner en « Create a merge commit » (pas de squash)."
            elif [[ "$head" == "main" ]]; then
                flow_ok=true
                merge_hint="Back-merge main → staging après un hotfix : fusionner en « Create a merge commit »."
            elif [[ "$head" =~ ^hotfix/.+ ]]; then
                flow_ok=true
                merge_hint="Hotfix porté sur staging : fusionner en « Create a merge commit »."
            else
                fail "Flux de branches refusé" \
                    "staging (pré-production) n'accepte que dev, main (back-merge) ou une branche hotfix/<sujet>, pas « ${head} ». Une branche de travail vise dev. Voir ${DOC_URL}"
            fi
            ;;
        dev)
            if [[ "$head" == "staging" || "$head" == "main" ]]; then
                flow_ok=true
                merge_hint="Back-merge ${head} → dev : fusionner en « Create a merge commit » (pas de squash)."
            elif [[ "$head" =~ ^(${WORK_PREFIXES})/.+ ]]; then
                flow_ok=true
                merge_hint="Branche de travail : fusionner en « Squash and merge » (un commit par PR sur dev)."
            else
                fail "Nom de branche refusé" \
                    "« ${head} » ne suit pas la convention <type>/<sujet>. Préfixes acceptés : ${WORK_PREFIXES//|/, }. Exemple : feature/mart-epargne. Renommez la branche (git branch -m) puis rouvrez la PR. Voir ${DOC_URL}"
            fi
            ;;
        *)
            fail "Branche cible inconnue" \
                "La branche cible « ${base} » n'a pas de règle. Les PR visent dev (intégration), staging (pré-production) ou main (production)."
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# 2. Titre Conventional Commits
# ---------------------------------------------------------------------------
title_ok=false
title_type=""
hint="Format attendu : type(portée)!: description. Types : ${TITLE_TYPES//|/, }. Exemples : « feat(marts): ajouter mart_epargne », « fix: corriger le solde mensuel », « release: dev → staging »."
if [[ "$title" =~ $TITLE_REGEX ]]; then
    title_type="${BASH_REMATCH[1]}"
    description="${BASH_REMATCH[3]}"
    if [[ "$description" =~ [^[:space:]] ]]; then
        title_ok=true
    else
        fail "Titre de PR invalide" "La description après « ${title_type}: » est vide. ${hint}"
    fi
elif [[ -z "${title//[[:space:]]/}" ]]; then
    fail "Titre de PR invalide" "Le titre est vide. ${hint}"
elif [[ "$title" =~ ^Revert\ \" ]]; then
    fail "Titre de PR invalide" "Titre généré par le bouton Revert de GitHub : renommez-le en « revert: <titre d'origine> ». ${hint}"
elif [[ "$title" =~ ^([A-Za-z]+)(\(.*\))?!?: ]]; then
    typed="${BASH_REMATCH[1]}"
    lower="$(printf '%s' "$typed" | tr '[:upper:]' '[:lower:]')"
    if [[ ! "$typed" =~ ^(${TITLE_TYPES})$ ]]; then
        if [[ "$lower" =~ ^(${TITLE_TYPES})$ ]]; then
            fail "Titre de PR invalide" "Le type s'écrit en minuscules : « ${lower} » et non « ${typed} ». ${hint}"
        else
            fail "Titre de PR invalide" "Type « ${typed} » inconnu. ${hint}"
        fi
    elif [[ "$title" =~ ^[a-z]+\( ]] && [[ ! "$title" =~ ^[a-z]+\([a-z0-9._/-]+\)!?: ]]; then
        fail "Titre de PR invalide" "La portée entre parenthèses n'accepte que des minuscules, des chiffres et . _ / - (exemple : feat(marts): …). ${hint}"
    elif [[ "$title" =~ ^[a-z]+(\([^\)]*\))?!?:[[:space:]]*$ ]]; then
        fail "Titre de PR invalide" "La description après les deux-points est vide. ${hint}"
    elif [[ "$title" =~ ^[a-z]+(\([^\)]*\))?!?:[^[:space:]] ]]; then
        fail "Titre de PR invalide" "Il manque une espace après les deux-points. ${hint}"
    else
        fail "Titre de PR invalide" "« ${title} » ne suit pas Conventional Commits. ${hint}"
    fi
else
    fail "Titre de PR invalide" "« ${title} » ne suit pas Conventional Commits. ${hint}"
fi

# ---------------------------------------------------------------------------
# 3. Conseils (n'échouent jamais)
# ---------------------------------------------------------------------------
if $flow_ok && $title_ok; then
    is_promotion=false
    if [[ "$base" == "staging" && "$head" == "dev" ]] || [[ "$base" == "main" && "$head" == "staging" ]]; then
        is_promotion=true
    fi
    if $is_promotion && [[ "$title_type" != "release" ]]; then
        warn "Titre de release conseillé" "Une PR de promotion s'appelle « release: ${head} → ${base} » (ou « release(x.y.z): … »)."
    fi
    if [[ "$base" == "main" && "$head" =~ ^hotfix/ ]]; then
        note "Back-merge à prévoir" "Après la fusion du hotfix, ouvrir les PR de back-merge main → staging puis staging → dev (merge commit)."
    fi
fi

# ---------------------------------------------------------------------------
# Résumé
# ---------------------------------------------------------------------------
if (( errors == 0 )); then
    echo "PR conforme : ${head} → ${base}, titre « ${title} »."
    [[ -n "$merge_hint" ]] && echo "$merge_hint"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo "## Politique de PR"
        echo
        echo "| Contrôle | Résultat |"
        echo "|---|---|"
        if $flow_ok; then
            echo "| Flux \`${head}\` → \`${base}\` | conforme |"
        else
            echo "| Flux \`${head}\` → \`${base}\` | **refusé** |"
        fi
        if $title_ok; then
            echo "| Titre (Conventional Commits) | conforme |"
        else
            echo "| Titre (Conventional Commits) | **invalide** |"
        fi
        echo
        if [[ -n "$merge_hint" ]]; then
            echo "**Fusion** : ${merge_hint}"
            echo
        fi
        if (( ${#summary_lines[@]} > 0 )); then
            printf '%s\n' "${summary_lines[@]}"
            echo
        fi
        echo "Règles complètes : ${DOC_URL}"
    } >> "$GITHUB_STEP_SUMMARY"
fi

if (( errors > 0 )); then
    echo "${errors} problème(s) à corriger. Le titre se modifie directement sur la PR ; ce contrôle se relance tout seul." >&2
    exit 1
fi
