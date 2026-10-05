with source as (

    select * from {{ source('raw', 'raw_comptes') }}

),

renamed as (

    select
        id as compte_id,
        nom_client,
        email,
        type_compte,
        date_ouverture,
        solde_initial,
        lower(statut) as statut

    from source

)

select * from renamed
