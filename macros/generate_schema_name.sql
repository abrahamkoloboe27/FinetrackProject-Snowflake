{#-
    Surcharge de la macro native de dbt : choisit le schéma Snowflake de
    chaque modèle selon l'environnement (la target dbt).

    Par défaut, dbt concatène le schéma du profil et le schéma
    personnalisé (+schema) : avec un profil sur STAGING, un modèle
    configuré avec +schema: marts irait dans STAGING_MARTS. Ce comportement
    est gardé partout, sauf en production :

      target prod : le schéma personnalisé est utilisé tel quel. Les
                    modèles de models/staging vont dans STAGING, ceux de
                    models/marts dans MARTS (schémas historiques du projet).
      autre target : le schéma du profil sert de préfixe. Chaque
                    environnement a ainsi ses propres schémas :
                      dev (CD)        DEV          → DEV_STAGING, DEV_MARTS
                      staging (CD)    PREPROD      → PREPROD_STAGING, PREPROD_MARTS
                      ci (PR n° 12)   CI_PR_12     → CI_PR_12_STAGING, CI_PR_12_MARTS
                      poste local     DEV_ABRAHAM  → DEV_ABRAHAM_STAGING, ...

    Un modèle sans +schema reste dans le schéma du profil (prod : STAGING).
    Le nom est mis en majuscules, comme Snowflake stocke les identifiants
    non cités : il apparaît ainsi à l'identique dans Snowflake, dans la
    documentation dbt et pour la macro drop_ci_schemas.

    ⚠ Seule la target nommée exactement « prod » écrit dans STAGING et
      MARTS. Ne donnez jamais ce nom à une target de votre profil local.
      Une target autre que prod sur le schéma STAGING ou MARTS (ancien
      profil local, schema: STAGING) est refusée, avec un message : elle
      construirait sinon en silence dans STAGING_STAGING et STAGING_MARTS.

    Les schémas de dev, de recette et de CI sont créés à la volée par dbt :
    FINTRACK_ROLE doit avoir le droit CREATE SCHEMA sur FINTRACK_DB
    (voir snowflake/04_ci_cd.sql).
-#}

{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- if target.name != 'prod' and (target.schema | trim | upper) in ['STAGING', 'MARTS'] -%}
        {{ exceptions.raise_compiler_error(
            "Le schéma " ~ target.schema ~ " de la target " ~ target.name
            ~ " est réservé à la production. Dans votre profil, mettez schema: DEV_<PRENOM> (voir docs/demarrage.md).") }}
    {%- endif -%}

    {%- if custom_schema_name is none -%}
        {{ target.schema | trim | upper }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim | upper }}
    {%- else -%}
        {{ (target.schema | trim ~ '_' ~ custom_schema_name | trim) | upper }}
    {%- endif -%}

{%- endmacro %}
