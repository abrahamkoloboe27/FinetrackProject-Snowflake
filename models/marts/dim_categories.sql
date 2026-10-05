with categories as (

    select * from {{ ref('stg_categories') }}

)

select
    categorie_id,
    nom_categorie,
    type_categorie,
    groupe

from categories
