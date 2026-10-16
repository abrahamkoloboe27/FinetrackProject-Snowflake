#!/usr/bin/env python3
"""Masque le compte et l'utilisateur Snowflake dans les fichiers publiés.

Le dépôt est public : tout compte GitHub connecté peut télécharger les
artefacts d'une exécution, et GitHub ne masque les secrets que dans les
journaux de la console, pas dans les fichiers d'artefact. dbt debug est
lancé avec --log-level-file none, mais une erreur de connexion pendant le
build écrit encore l'URL du compte dans logs/dbt.log
(« Failed to connect to DB: <compte>.snowflakecomputing.com:443 »).

Avant chaque publication d'artefact, ce script remplace par *** les valeurs
de SNOWFLAKE_ACCOUNT et SNOWFLAKE_USER (lues dans l'environnement, sans
tenir compte de la casse) dans les fichiers indiqués, par défaut
logs/dbt.log et target/run_results.json. target/manifest.json n'est pas
touché : il ne contient aucun identifiant et sert de référence à la Slim CI.

Les valeurs ne sont jamais affichées : seul le nombre de remplacements par
fichier l'est. Une variable vide ou un fichier absent sont ignorés. Le code
de sortie vaut toujours 0 : ce script ne doit jamais faire échouer un job.

Usage :
  python3 scripts/ci/redact_artifacts.py [fichier ...]
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

DEFAULT_FILES = ["logs/dbt.log", "target/run_results.json"]
VARIABLES = ["SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER"]
MASK = b"***"


def patterns() -> list[re.Pattern[bytes]]:
    """Expressions à masquer, sans jamais exposer les valeurs."""
    values: set[str] = set()
    for name in VARIABLES:
        value = os.environ.get(name, "").strip()
        if not value:
            continue
        values.add(value)
        # Dans l'URL du compte, le connecteur remplace « _ » par « - ».
        values.add(value.replace("_", "-"))
    # Les plus longues d'abord : une valeur contenue dans une autre ne
    # laisse pas de morceau en clair.
    ordered = sorted(values, key=len, reverse=True)
    return [re.compile(re.escape(v.encode("utf-8")), re.IGNORECASE) for v in ordered]


def redact(path: Path, compiled: list[re.Pattern[bytes]]) -> int:
    """Masque les valeurs dans un fichier ; renvoie le nombre de remplacements."""
    data = path.read_bytes()
    total = 0
    for pattern in compiled:
        data, count = pattern.subn(MASK, data)
        total += count
    if total:
        path.write_bytes(data)
    return total


def main(argv: list[str]) -> int:
    compiled = patterns()
    if not compiled:
        print("Masquage : SNOWFLAKE_ACCOUNT et SNOWFLAKE_USER vides, rien à masquer.")
        return 0
    for name in argv or DEFAULT_FILES:
        path = Path(name)
        if not path.is_file():
            print(f"Masquage : {name} absent, ignoré.")
            continue
        try:
            count = redact(path, compiled)
        except OSError as error:
            print(f"::warning title=Masquage::{name} illisible ({error.strerror}).")
            continue
        print(f"Masquage : {name}, {count} occurrence(s) remplacée(s) par ***.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
