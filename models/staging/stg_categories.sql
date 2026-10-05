with source as (

    select * from {{ source('raw', 'raw_categories') }}

),

renamed as (

    select
        id as categorie_id,
        nom as nom_categorie,
        type as type_categorie,
        groupe

    from source

)

select * from renamed
