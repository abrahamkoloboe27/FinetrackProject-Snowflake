{#-
    Nettoyage des schémas temporaires de la CI.

    Chaque pull request construit le projet dans ses propres schémas,
    CI_PR_<numéro>_STAGING et CI_PR_<numéro>_MARTS (voir la macro
    generate_schema_name). Cette macro les supprime quand ils ne servent
    plus. Elle est appelée par le workflow « CI cleanup » :

      -- schémas d'une PR précise (à la fermeture de la PR)
      dbt run-operation drop_ci_schemas --target ci --args '{pr_number: 12}'

      -- tous les schémas CI_PR_*, sauf ceux des PR encore ouvertes
      -- (ménage hebdomadaire ; une liste vide supprime tout)
      dbt run-operation drop_ci_schemas --target ci --args '{keep_pr_numbers: [3, 7]}'

      -- simulation : liste ce qui serait supprimé, sans rien supprimer
      dbt run-operation drop_ci_schemas --target ci --args '{pr_number: 12, dry_run: true}'

    Garde-fous :
      - exactement UN des deux paramètres, pr_number ou keep_pr_numbers ;
        un numéro qui n'est pas un entier positif arrête tout ;
      - la sélection se fait en Jinja, jamais avec LIKE : dans un motif
        LIKE, « _ » remplace n'importe quel caractère, et CI_PR_1_%
        engloberait aussi CI_PR_12_STAGING ;
      - seul un schéma dont le nom commence par CI_PR_<numéro>, suivi de
        « _ » ou de rien, est retenu (casse ignorée). Le numéro est comparé
        en entier : 1 ne désigne jamais 12. STAGING, MARTS, DEV_*,
        PREPROD_* ou CI_LOCAL_* ne sont jamais touchés ;
      - le nom est repris tel que Snowflake le renvoie et cité entre
        guillemets : la commande DROP vise exactement le schéma listé ;
      - chaque suppression est écrite dans le journal.

    La sélection est isolée dans ci_schemas_to_drop, une macro pure (sans
    requête). drop_ci_schemas_selftest la vérifie sans connexion à
    Snowflake :
      dbt run-operation drop_ci_schemas_selftest --target ci
-#}

{% macro drop_ci_schemas(pr_number=none, keep_pr_numbers=none, dry_run=false) %}

    {%- if not execute -%}
        {{ return(none) }}
    {%- endif -%}

    {%- set simulation = (dry_run | string | trim | lower) in ['true', '1', 'yes', 'oui'] -%}

    {#- Paramètres vérifiés avant toute requête : une erreur d'appel
        s'arrête ici, sans rien lister ni supprimer. -#}
    {%- do ci_schemas_to_drop([], pr_number, keep_pr_numbers) -%}

    {%- set listing = run_query(
        'show terse schemas in database ' ~ target.database ~ ' limit 10000') -%}
    {%- set schemas = listing.columns['name'].values() | list -%}
    {%- set to_drop = ci_schemas_to_drop(schemas, pr_number, keep_pr_numbers) -%}

    {%- if pr_number is not none -%}
        {%- set mode = 'pr_number=' ~ pr_number -%}
    {%- else -%}
        {%- set mode = 'keep_pr_numbers=[' ~ (keep_pr_numbers | join(', ')) ~ ']' -%}
    {%- endif -%}

    {{ log('drop_ci_schemas (' ~ mode ~ (', simulation' if simulation else '') ~ ') : '
           ~ schemas | length ~ ' schéma(s) dans ' ~ target.database ~ ', '
           ~ to_drop | length ~ ' à supprimer.', info=True) }}

    {%- for schema_name in to_drop -%}

        {#- Défense en profondeur : la sélection l'a déjà garanti. -#}
        {%- if ci_schema_pr_number(schema_name) is none -%}
            {{ exceptions.raise_compiler_error(
                "drop_ci_schemas : refus de supprimer " ~ schema_name
                ~ ", qui n'est pas un schéma CI_PR_<numéro>.") }}
        {%- endif -%}

        {%- set drop_sql = 'drop schema if exists ' ~ target.database ~ '.'
                           ~ '"' ~ (schema_name | replace('"', '""')) ~ '"' ~ ' cascade' -%}

        {%- if simulation -%}
            {{ log('  [simulation] ' ~ drop_sql, info=True) }}
        {%- else -%}
            {%- do run_query(drop_sql) -%}
            {{ log('  supprimé : ' ~ target.database ~ '.' ~ schema_name, info=True) }}
        {%- endif -%}

    {%- endfor -%}

    {%- if to_drop | length == 0 -%}
        {{ log('  Aucun schéma CI à supprimer.', info=True) }}
    {%- endif -%}

{% endmacro %}


{#-
    Sélection des schémas à supprimer (macro pure : aucune requête).

    schemas          noms de schémas, tels que Snowflake les renvoie
    pr_number        supprime les schémas de cette PR
    keep_pr_numbers  liste des PR à garder : supprime tous les autres
                     schémas CI_PR_<numéro>

    Renvoie la liste triée des noms retenus, avec leur casse d'origine.
-#}

{% macro ci_schemas_to_drop(schemas, pr_number=none, keep_pr_numbers=none) %}

    {%- if (pr_number is none) == (keep_pr_numbers is none) -%}
        {{ exceptions.raise_compiler_error(
            'drop_ci_schemas : précisez exactement un paramètre, '
            ~ 'pr_number (ex. {pr_number: 12}) '
            ~ 'OU keep_pr_numbers (ex. {keep_pr_numbers: [3, 7]}).') }}
    {%- endif -%}

    {%- set kept = [] -%}
    {%- set target_pr = none -%}

    {%- if pr_number is not none -%}
        {%- set target_pr = ci_pr_number_to_int(pr_number, 'pr_number') -%}
    {%- else -%}
        {%- if keep_pr_numbers is string
              or keep_pr_numbers is mapping
              or keep_pr_numbers is not iterable -%}
            {{ exceptions.raise_compiler_error(
                'drop_ci_schemas : keep_pr_numbers doit être une liste de numéros, '
                ~ 'ex. {keep_pr_numbers: [3, 7]} (ou [] pour tout supprimer). '
                ~ 'Reçu : ' ~ keep_pr_numbers) }}
        {%- endif -%}
        {%- for value in keep_pr_numbers -%}
            {%- do kept.append(ci_pr_number_to_int(value, 'keep_pr_numbers')) -%}
        {%- endfor -%}
    {%- endif -%}

    {%- set selection = [] -%}
    {%- for schema_name in schemas | sort -%}
        {%- set number = ci_schema_pr_number(schema_name) -%}
        {%- if number is not none -%}
            {%- if target_pr is not none and number == target_pr -%}
                {%- do selection.append(schema_name) -%}
            {%- elif target_pr is none and number not in kept -%}
                {%- do selection.append(schema_name) -%}
            {%- endif -%}
        {%- endif -%}
    {%- endfor -%}

    {{ return(selection) }}

{% endmacro %}


{#- Numéro de PR d'un schéma CI_PR_<numéro>[_...] (entier), sinon none. -#}

{% macro ci_schema_pr_number(schema_name) %}

    {%- set found = modules.re.match('^CI_PR_([0-9]+)(_|$)', schema_name | string | upper) -%}
    {{ return(found.group(1) | int if found else none) }}

{% endmacro %}


{#-
    Convertit un numéro de PR reçu en paramètre en entier. Avec --args,
    12 arrive en entier et '12' en texte : les deux sont acceptés. Tout le
    reste (texte, nombre négatif ou décimal, booléen, vide) arrête la
    macro : mieux vaut ne rien supprimer que mal interpréter un numéro.
-#}

{% macro ci_pr_number_to_int(value, param_name) %}

    {%- set text = value | string | trim -%}
    {%- if not modules.re.fullmatch('[0-9]+', text) -%}
        {{ exceptions.raise_compiler_error(
            'drop_ci_schemas : ' ~ param_name ~ ' attend des numéros de PR '
            ~ '(entiers positifs). Reçu : « ' ~ value ~ ' ».') }}
    {%- endif -%}
    {{ return(text | int) }}

{% endmacro %}


{#-
    Auto-test de la sélection, sans connexion à Snowflake. Échoue si un
    cas ne donne pas le résultat attendu.
      dbt run-operation drop_ci_schemas_selftest --target ci
-#}

{% macro drop_ci_schemas_selftest() %}

    {%- set schemas = [
        'CI_PR_1_STAGING', 'CI_PR_12_STAGING', 'CI_PR_1_MARTS', 'CI_PR_12',
        'STAGING', 'MARTS', 'DEV_STAGING', 'PREPROD_MARTS', 'CI_LOCAL_STAGING',
        'CI_PR_X_FOO', 'CI_PR_7ABC_STAGING', 'PREPROD_CI_PR_1_STAGING', 'ci_pr_3_marts'
    ] -%}

    {#- (libellé, pr_number, keep_pr_numbers, schémas attendus) -#}
    {%- set cases = [
        ('pr_number=1', 1, none, ['CI_PR_1_MARTS', 'CI_PR_1_STAGING']),
        ("pr_number='12'", '12', none, ['CI_PR_12', 'CI_PR_12_STAGING']),
        ('pr_number=3', 3, none, ['ci_pr_3_marts']),
        ('pr_number=99', 99, none, []),
        ('keep_pr_numbers=[12]', none, [12],
            ['CI_PR_1_MARTS', 'CI_PR_1_STAGING', 'ci_pr_3_marts']),
        ("keep_pr_numbers=['1', 3]", none, ['1', 3], ['CI_PR_12', 'CI_PR_12_STAGING']),
        ('keep_pr_numbers=[1, 3, 12]', none, [1, 3, 12], []),
        ('keep_pr_numbers=[]', none, [],
            ['CI_PR_1_MARTS', 'CI_PR_1_STAGING', 'CI_PR_12', 'CI_PR_12_STAGING',
             'ci_pr_3_marts'])
    ] -%}

    {%- set failures = [] -%}
    {%- for label, pr, keep, expected in cases -%}
        {%- set got = ci_schemas_to_drop(schemas, pr, keep) -%}
        {%- set ok = (got | sort) == (expected | sort) -%}
        {{ log(('  OK     ' if ok else '  ÉCHEC  ') ~ label ~ ' → '
               ~ (got | join(', ') or '(rien)'), info=True) }}
        {%- if not ok -%}
            {%- do failures.append(label ~ ' : attendu ' ~ (expected | join(', '))
                                   ~ ', obtenu ' ~ (got | join(', '))) -%}
        {%- endif -%}
    {%- endfor -%}

    {#- Le bilan est journalisé AVANT l'erreur : sans identifiants Snowflake,
        dbt run-operation remplace le message d'erreur final par
        « Password is empty » (il tente une connexion pour annuler une
        éventuelle transaction). Le code de sortie reste 1. -#}
    {%- if failures | length > 0 -%}
        {{ log('drop_ci_schemas_selftest : ' ~ failures | length ~ ' cas en ÉCHEC (détail '
               ~ 'ci-dessus) : la sélection des schémas à supprimer est incorrecte.', info=True) }}
        {{ exceptions.raise_compiler_error(
            'drop_ci_schemas_selftest : ' ~ failures | join(' | ')) }}
    {%- endif -%}
    {{ log('drop_ci_schemas_selftest : ' ~ cases | length
           ~ ' cas vérifiés, sélection conforme.', info=True) }}

{% endmacro %}
