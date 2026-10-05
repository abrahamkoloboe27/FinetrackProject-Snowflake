with transactions as (

    select * from {{ ref('stg_transactions') }}

),

comptes as (

    select
        compte_id,
        nom_client,
        type_compte

    from {{ ref('stg_comptes') }}

),

categories as (

    select
        categorie_id,
        nom_categorie,
        type_categorie,
        groupe

    from {{ ref('stg_categories') }}

),

enrichies as (

    select
        transactions.transaction_id,
        transactions.compte_id,
        transactions.date_transaction,
        transactions.montant,
        transactions.type_operation,
        transactions.categorie_id,
        transactions.description,
        transactions.statut,
        transactions.montant_signe,

        comptes.nom_client,
        comptes.type_compte,

        categories.nom_categorie,
        categories.type_categorie,
        categories.groupe,

        -- premier jour du mois de la transaction, en DATE
        cast(date_trunc('month', transactions.date_transaction) as date) as mois_transaction

    from transactions
    -- left join : une transaction dont le compte ou la catégorie serait
    -- introuvable reste visible (les tests relationships la signalent)
    left join comptes
        on transactions.compte_id = comptes.compte_id
    left join categories
        on transactions.categorie_id = categories.categorie_id

)

select * from enrichies
