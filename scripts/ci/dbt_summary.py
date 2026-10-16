#!/usr/bin/env python3
"""Résumé d'un run dbt pour la page de synthèse d'un job GitHub Actions.

Lit target/run_results.json (écrit par dbt build, run, test, seed...) et
produit un résumé en Markdown :
  - un tableau par statut (success, pass, warn, error, fail, skipped...)
    avec le nombre de nœuds et la durée cumulée ;
  - le détail des échecs et des avertissements (unique_id + message tronqué).

Le résumé est ajouté à $GITHUB_STEP_SUMMARY, ou affiché sur la sortie
standard hors de GitHub Actions.

Le code de sortie vaut toujours 0 : le statut du job vient de dbt, pas de
ce script. Un fichier absent ou illisible donne un simple message.

Usage :
  python scripts/ci/dbt_summary.py "dbt build (CI) - PR #12"
  python scripts/ci/dbt_summary.py "Titre" --run-results chemin/run_results.json
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# Ordre d'affichage des statuts connus ; les autres suivent par ordre alphabétique.
STATUS_ORDER = ["success", "pass", "warn", "error", "fail", "runtime error", "skipped", "no-op"]
FAILED_STATUSES = {"error", "fail", "runtime error", "partial success"}
WARN_STATUSES = {"warn"}
MAX_MESSAGE = 300


def clean(text: object, limit: int = MAX_MESSAGE) -> str:
    """Rend un texte sûr dans une cellule de tableau Markdown."""
    value = " ".join(str(text or "").split())
    if len(value) > limit:
        value = value[: limit - 1] + "…"
    return value.replace("|", "\\|").replace("`", "'")


def fmt_seconds(seconds: float) -> str:
    if seconds >= 60:
        minutes, rest = divmod(seconds, 60)
        return f"{int(minutes)} min {rest:04.1f} s"
    return f"{seconds:.1f} s"


def detail_table(rows: list[dict], max_rows: int) -> list[str]:
    lines = ["| Nœud | Statut | Message |", "|---|---|---|"]
    for row in rows[:max_rows]:
        message = row.get("message")
        failures = row.get("failures")
        if failures and not message:
            message = f"{failures} ligne(s) en échec"
        lines.append(
            f"| `{clean(row.get('unique_id', '?'), 150)}` | {clean(row.get('status'))} | {clean(message)} |"
        )
    if len(rows) > max_rows:
        lines.append(f"| … | | {len(rows) - max_rows} autre(s) non affiché(s) |")
    return lines


def build_summary(title: str, path: Path, max_rows: int) -> str:
    lines = [f"## {title}", ""]

    if not path.is_file():
        lines.append(
            f"Aucun fichier `{path}` : dbt ne s'est pas exécuté "
            "(étape précédente en échec, secrets absents ou rien à construire)."
        )
        return "\n".join(lines) + "\n"

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        results = data.get("results") or []
        if not isinstance(results, list):
            raise ValueError("champ « results » inattendu")
    except (OSError, ValueError, AttributeError) as exc:
        lines.append(f"Fichier `{path}` illisible : {clean(exc)}")
        return "\n".join(lines) + "\n"

    metadata = data.get("metadata") or {}
    args = data.get("args") or {}
    infos = []
    if args.get("which"):
        infos.append(f"commande `dbt {clean(args['which'], 40)}`")
    if args.get("target"):
        infos.append(f"target `{clean(args['target'], 40)}`")
    if args.get("select"):
        select = args["select"]
        if isinstance(select, list):
            select = " ".join(str(s) for s in select)
        infos.append(f"sélection `{clean(select, 120)}`")
    if metadata.get("dbt_version"):
        infos.append(f"dbt {clean(metadata['dbt_version'], 20)}")
    elapsed = data.get("elapsed_time")
    if isinstance(elapsed, (int, float)):
        infos.append(f"durée totale {fmt_seconds(float(elapsed))}")
    if infos:
        lines += [", ".join(infos), ""]

    if not results:
        lines.append("Aucun nœud exécuté (sélection vide : rien n'a changé).")
        return "\n".join(lines) + "\n"

    counts: dict[str, int] = {}
    durations: dict[str, float] = {}
    for row in results:
        status = str(row.get("status") or "inconnu").lower()
        counts[status] = counts.get(status, 0) + 1
        try:
            durations[status] = durations.get(status, 0.0) + float(row.get("execution_time") or 0)
        except (TypeError, ValueError):
            durations.setdefault(status, 0.0)

    ordered = [s for s in STATUS_ORDER if s in counts]
    ordered += sorted(s for s in counts if s not in STATUS_ORDER)

    lines += ["| Statut | Nœuds | Durée cumulée |", "|---|---:|---:|"]
    for status in ordered:
        label = f"**{status}**" if status in FAILED_STATUSES else status
        lines.append(f"| {label} | {counts[status]} | {fmt_seconds(durations[status])} |")
    lines.append(f"| **total** | **{len(results)}** | {fmt_seconds(sum(durations.values()))} |")
    lines.append("")

    failed = [r for r in results if str(r.get("status") or "").lower() in FAILED_STATUSES]
    warned = [r for r in results if str(r.get("status") or "").lower() in WARN_STATUSES]

    if failed:
        lines += [f"### Échecs ({len(failed)})", ""]
        lines += detail_table(failed, max_rows)
        lines += ["", "Détail complet : artefact du job (logs/dbt.log, target/run_results.json).", ""]
    if warned:
        lines += [f"### Avertissements ({len(warned)})", ""]
        lines += detail_table(warned, max_rows)
        lines.append("")
    if not failed and not warned:
        lines.append("Tous les nœuds sont passés sans erreur ni avertissement.")

    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Résumé Markdown d'un run dbt (run_results.json).")
    parser.add_argument("title", nargs="?", default="Résumé dbt", help="titre de la section")
    parser.add_argument(
        "--run-results",
        default="target/run_results.json",
        help="chemin du fichier run_results.json (défaut : target/run_results.json)",
    )
    parser.add_argument("--max-rows", type=int, default=25, help="lignes de détail affichées au maximum")
    options = parser.parse_args(argv)

    try:
        summary = build_summary(options.title, Path(options.run_results), max(1, options.max_rows))
    except Exception as exc:  # noqa: BLE001 - un résumé ne doit jamais faire échouer le job
        summary = f"## {options.title}\n\nRésumé indisponible : {clean(exc)}\n"

    target = os.environ.get("GITHUB_STEP_SUMMARY")
    if target:
        try:
            with open(target, "a", encoding="utf-8") as handle:
                handle.write(summary + "\n")
            print(f"Résumé ajouté à la synthèse du job ({options.run_results}).")
            return 0
        except OSError as exc:
            print(f"Impossible d'écrire dans GITHUB_STEP_SUMMARY : {exc}", file=sys.stderr)
    sys.stdout.write(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
