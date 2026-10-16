# =====================================================================
# FinTrack Analytics : raccourcis du projet
#
# `make` (ou `make help`) liste les commandes. Elles utilisent les outils
# de l'environnement virtuel .venv créé par `make install`, ou à défaut
# ceux du PATH.
#
# build, test, debug et dbt-docs se connectent à Snowflake avec VOTRE
# profil ~/.dbt/profiles.yml (target dev, schéma DEV_<PRENOM> : voir la
# documentation, page « Démarrage »). parse, lint et docs n'ont besoin
# d'aucune connexion : ce sont les mêmes contrôles que la CI.
#
# Variables, à passer en ligne de commande :
#   make build SELECT=stg_comptes+   sous-ensemble du DAG (option --select)
#   make build TARGET=dev            target dbt de votre profil (dev par défaut)
#   make install PYTHON=python3.13   interpréteur utilisé pour créer .venv
# =====================================================================

SHELL         := /bin/bash
.SHELLFLAGS   := -eu -o pipefail -c
.DEFAULT_GOAL := help

# Interpréteur pour créer .venv : python3.12 (version de la CI, voir
# .python-version) s'il est installé, sinon python3.13, python3.11, python3.
ifndef PYTHON
PYTHON := $(or $(firstword $(foreach p,python3.12 python3.13 python3.11 python3,\
            $(shell command -v $(p) 2>/dev/null))),python3.12)
endif

VENV          ?= .venv
TARGET        ?= dev
SELECT        ?=
DBT_DOCS_PORT ?= 8080

# Outils de .venv s'il existe, sinon ceux du PATH. Affectation « = » :
# évaluée à l'usage, donc après la création de .venv par `make install`.
BIN         = $(if $(wildcard $(VENV)/bin/python),$(VENV)/bin/,)
DBT         = $(BIN)dbt
PRE_COMMIT  = $(BIN)pre-commit
SQLFLUFF    = $(BIN)sqlfluff
MKDOCS      = NO_MKDOCS_2_WARNING=true $(BIN)mkdocs

SELECT_ARG  = $(if $(SELECT),--select $(SELECT),)

# Contrôle hors-ligne, identique au job « dbt parse » de la CI : profil
# ci/profiles.yml et identifiants factices (non vides, sinon le profil
# est invalide). dbt ne se connecte pas pour parse.
OFFLINE_ENV = DBT_PROFILES_DIR=ci SNOWFLAKE_ACCOUNT=ci-offline SNOWFLAKE_USER=ci-offline

.PHONY: help install deps lint fix parse debug build test docs docs-serve dbt-docs clean

help: ## Affiche cette aide
	@printf 'FinTrack Analytics : commandes disponibles (make <commande>)\n\n'
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z0-9_-]+:.*## / { printf "  %-11s %s\n", $$1, $$2 }' \
		$(MAKEFILE_LIST)
	@printf '\nVariables : TARGET=%s (target dbt), SELECT=<sélection dbt>, PYTHON=%s\n' \
		'$(TARGET)' '$(PYTHON)'
	@printf 'Exemple   : make build SELECT=stg_comptes+\n'

install: ## Crée .venv, installe les dépendances de dev et le hook pre-commit
	@command -v $(PYTHON) >/dev/null || { \
		echo "$(PYTHON) introuvable : installez Python 3.12, ou précisez PYTHON=..." >&2; exit 1; }
	@$(PYTHON) -c 'import sys; sys.exit(sys.version_info[:2] < (3, 11))' || { \
		echo "$(PYTHON) est trop ancien : Python 3.11 minimum, 3.12 recommandé (celui de la CI)" >&2; \
		exit 1; }
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/python -m pip install --upgrade pip
	$(VENV)/bin/python -m pip install -r requirements-dev.txt
	$(VENV)/bin/pre-commit install --install-hooks
	@echo "Environnement prêt. Activez-le avec : source $(VENV)/bin/activate (puis make deps)"

deps: ## Installe les packages dbt (dbt_utils, codegen) selon package-lock.yml
	$(DBT) deps
	@touch dbt_packages

# Packages dbt installés automatiquement avant parse, build, test... s'ils
# manquent ou si packages.yml / package-lock.yml ont changé depuis.
dbt_packages: packages.yml package-lock.yml
	$(DBT) deps
	@touch dbt_packages

lint: ## Lance tous les contrôles pre-commit sur tout le dépôt (comme la CI)
	$(PRE_COMMIT) run --all-files --show-diff-on-failure

fix: ## Corrige automatiquement le style SQL (sqlfluff fix)
	$(SQLFLUFF) fix models tests analyses

parse: dbt_packages ## Vérifie le projet dbt sans connexion à Snowflake (comme la CI)
	$(OFFLINE_ENV) $(DBT) parse --target ci --warn-error
	$(OFFLINE_ENV) $(DBT) ls --target ci --resource-type model

debug: ## Vérifie le profil et la connexion à Snowflake (dbt debug)
	$(DBT) debug --target $(TARGET)

build: dbt_packages ## Construit les modèles et lance les tests (dbt build) dans vos schémas
	$(DBT) build --target $(TARGET) $(SELECT_ARG)

test: dbt_packages ## Lance uniquement les tests dbt
	$(DBT) test --target $(TARGET) $(SELECT_ARG)

docs: ## Construit le site de documentation (mkdocs build --strict) dans site/
	$(MKDOCS) build --strict

docs-serve: ## Sert le site de documentation en local, rechargé à chaque modification
	$(MKDOCS) serve

dbt-docs: dbt_packages ## Génère la documentation dbt (catalogue, lineage) et l'ouvre
	$(DBT) docs generate --target $(TARGET)
	$(DBT) docs serve --target $(TARGET) --port $(DBT_DOCS_PORT)

clean: ## Supprime les fichiers générés (target, dbt_packages, logs, site)
	rm -rf target dbt_packages logs site prod-state
