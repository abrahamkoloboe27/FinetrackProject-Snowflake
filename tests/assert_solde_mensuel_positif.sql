-- Test singulier : retourne les lignes en erreur, zéro ligne = test réussi.
-- Un compte épargne ne doit jamais avoir un solde cumulé négatif.

select
    compte_id,
    nom_client,
    mois,
    solde_cumule

from {{ ref('mart_solde_mensuel') }}
where type_compte = 'epargne'
    and solde_cumule < 0
