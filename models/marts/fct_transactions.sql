with transactions as (

    select * from {{ ref('int_transactions_enrichies') }}

),

final as (

    select
        transaction_id,
        compte_id,
        categorie_id,
        date_transaction,
        mois_transaction,
        montant,
        montant_signe,
        type_operation,
        nom_client,
        nom_categorie,
        groupe,
        statut

    from transactions

    -- seules les transactions validées comptent dans les analyses
    where statut = 'validee'

)

select * from final
