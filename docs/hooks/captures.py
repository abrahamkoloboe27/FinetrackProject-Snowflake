"""Hook MkDocs : publie les captures d'écran du dossier assets/ sur le site.

Les captures vivent à un seul endroit : assets/, à la racine du dépôt, où le
README les affiche déjà (assets/lineage.png...). Ce hook les ajoute au site
sous le même chemin. Une page de docs/ les affiche donc avec
`![...](assets/<nom>.png)`, sans copie à maintenir, et `mkdocs build --strict`
vérifie le lien comme pour n'importe quel fichier de docs/.

Déclaré dans mkdocs.yml (clé `hooks`). Le dossier docs/hooks/ est exclu du
site (clé `exclude_docs`).
"""

from pathlib import Path

from mkdocs.structure.files import File

EXTENSIONS_IMAGES = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"}


def on_files(files, config):
    dossier = Path(config.config_file_path).parent / "assets"
    if not dossier.is_dir():
        return files

    for image in sorted(dossier.iterdir()):
        if image.suffix.lower() not in EXTENSIONS_IMAGES:
            continue
        chemin_site = f"assets/{image.name}"
        # une image du même nom placée dans docs/assets/ reste prioritaire
        if files.get_file_from_path(chemin_site) is None:
            files.append(File.generated(config, chemin_site, abs_src_path=str(image)))

    return files
