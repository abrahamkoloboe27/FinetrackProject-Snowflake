{#-
    Surcharge de la macro native de dbt.

    Par défaut, dbt construit le nom d'un schéma en concaténant le schéma du
    profil et le schéma personnalisé (+schema) : avec un profil sur STAGING,
    un modèle configuré avec +schema: marts irait dans STAGING_MARTS.
    Ce schéma n'existe pas et FINTRACK_ROLE n'a pas le droit de le créer.

    Ici, le schéma personnalisé est utilisé tel quel : les modèles de
    models/staging vont dans STAGING, ceux de models/marts dans MARTS, et
    tout modèle sans +schema reste dans le schéma du profil.
-#}

{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- if custom_schema_name is none -%}
        {{ target.schema | trim }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}

{%- endmacro %}
