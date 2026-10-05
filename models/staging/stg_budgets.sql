with source as (

    select * from {{ source('raw', 'raw_budgets') }}

),

renamed as (

    select
        id as budget_id,
        compte_id,
        categorie_id,
        cast(mois as date) as mois,
        montant_prevu

    from source

)

select * from renamed
