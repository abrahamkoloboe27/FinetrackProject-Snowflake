with transactions as (

    select * from {{ ref('fct_transactions') }}

),

comptes as (

    select
        compte_id,
        nom_client,
        type_compte,
        solde_initial

    from {{ ref('dim_comptes') }}

),

-- une ligne par (compte, mois) qui compte au moins une transaction validée
mensuel as (

    select
        compte_id,
        mois_transaction as mois,
        sum(case when type_operation = 'credit' then montant else 0 end) as total_credits,
        sum(case when type_operation = 'debit' then montant else 0 end) as total_debits

    from transactions
    group by compte_id, mois_transaction

),

final as (

    select
        mensuel.compte_id,
        comptes.nom_client,
        comptes.type_compte,
        mensuel.mois,
        mensuel.total_credits,
        mensuel.total_debits,
        mensuel.total_credits - mensuel.total_debits as solde_net,

        -- solde à l'ouverture + somme cumulée des soldes nets, mois après mois
        comptes.solde_initial
            + sum(mensuel.total_credits - mensuel.total_debits) over (
                partition by mensuel.compte_id
                order by mensuel.mois
                rows between unbounded preceding and current row
            ) as solde_cumule

    from mensuel
    left join comptes
        on mensuel.compte_id = comptes.compte_id

)

select * from final
