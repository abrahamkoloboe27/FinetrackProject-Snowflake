with budgets as (

    select
        compte_id,
        categorie_id,
        mois,
        sum(montant_prevu) as montant_prevu

    from {{ ref('stg_budgets') }}
    group by compte_id, categorie_id, mois

),

-- dépenses réelles : débits validés, par compte, catégorie et mois
depenses as (

    select
        compte_id,
        categorie_id,
        mois_transaction as mois,
        sum(montant) as montant_reel

    from {{ ref('fct_transactions') }}
    where type_operation = 'debit'
    group by compte_id, categorie_id, mois_transaction

),

-- full outer join : on garde les budgets sans dépense ET les dépenses sans budget
rapprochement as (

    select
        coalesce(budgets.compte_id, depenses.compte_id) as compte_id,
        coalesce(budgets.categorie_id, depenses.categorie_id) as categorie_id,
        coalesce(budgets.mois, depenses.mois) as mois,
        budgets.montant_prevu is not null as a_un_budget,
        coalesce(budgets.montant_prevu, 0) as montant_prevu,
        coalesce(depenses.montant_reel, 0) as montant_reel

    from budgets
    full outer join depenses
        on budgets.compte_id = depenses.compte_id
        and budgets.categorie_id = depenses.categorie_id
        and budgets.mois = depenses.mois

),

comptes as (

    select compte_id, nom_client from {{ ref('dim_comptes') }}

),

categories as (

    select categorie_id, nom_categorie from {{ ref('dim_categories') }}

),

final as (

    select
        rapprochement.compte_id,
        comptes.nom_client,
        rapprochement.categorie_id,
        categories.nom_categorie,
        rapprochement.mois,
        rapprochement.montant_prevu,
        rapprochement.montant_reel,

        -- écart > 0 : on a dépensé plus que prévu
        rapprochement.montant_reel - rapprochement.montant_prevu as ecart,

        -- dépassement uniquement si un budget existe : une dépense sans
        -- budget (montant_prevu = 0) n'est pas un dépassement de budget
        case
            when rapprochement.a_un_budget
                and rapprochement.montant_reel > rapprochement.montant_prevu
            then true
            else false
        end as depassement

    from rapprochement
    left join comptes
        on rapprochement.compte_id = comptes.compte_id
    left join categories
        on rapprochement.categorie_id = categories.categorie_id

)

select * from final
