with comptes as (

    select * from {{ ref('stg_comptes') }}

),

final as (

    select
        compte_id,
        nom_client,
        email,
        type_compte,
        date_ouverture,
        solde_initial,
        statut,

        -- nombre de jours écoulés entre l'ouverture du compte et aujourd'hui
        datediff('day', date_ouverture, current_date()) as anciennete_jours

    from comptes

)

select * from final
