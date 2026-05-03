# NAFAD PAY — Réponses aux 15 Questions Métier
Résultats issus du DWH G4 · 100 000 transactions · Année 2026 · Monnaie : MRU

---

## Section 1 — Performance Globale

### Q1 · Volume total ce mois vs mois précédent

| Mois courant (Déc) | Volume | Mois précédent (Nov) | Volume | Variation | Δ% |
|---|---|---|---|---|---|
| December | 152 325 350 MRU | November | 170 276 300 MRU | -17 950 950 MRU | **-10,5 %** |

> Le volume de décembre est en baisse de 10,5 % par rapport à novembre. À surveiller : possible saisonnalité de fin d'année ou ralentissement de l'activité.

---

### Q2 · Taux de succès des transactions

| Total transactions | Succès | Échecs | Taux de succès |
|---|---|---|---|
| 100 000 | 67 287 | 32 713 | **67,3 %** |

> 1 transaction sur 3 échoue. Le taux d'échec (32,7 %) est élevé et principalement dû aux soldes insuffisants (voir Q12).

---

### Q3 · Frais collectés

| Frais total | Frais moyen par transaction |
|---|---|
| **10 690 459 MRU** | 108,59 MRU |

> Soit environ 10,7 M MRU de revenus de frais sur l'année 2024 (hors transactions CONFLICT).

---

## Section 2 — Analyse Géographique

### Q4 · Wilaya qui génère le plus de volume (Top 5)

| Rang | Wilaya | Nb transactions | Volume (MRU) |
|---|---|---|---|
| 1 | **Nouakchott-Ouest** | 24 457 | 538 522 300 |
| 2 | Nouakchott-Nord | 20 517 | 417 181 300 |
| 3 | Nouakchott-Sud | 14 377 | 291 550 300 |
| 4 | Dakhlet Nouadhibou | 10 952 | 207 170 050 |
| 5 | Trarza | 4 821 | 103 494 100 |

> Nouakchott concentre ~60 % du volume total. Les 3 wilayas de Nouakchott dominent largement.

---

### Q5 · Agence la plus performante (Top 5)

| Rang | Agence | Wilaya | Nb transactions | Volume (MRU) |
|---|---|---|---|---|
| 1 | **Agence Dakhlet Nouadhibou 7** | Dakhlet Nouadhibou | 465 | 16 556 900 |
| 2 | Agence Nouakchott-Ouest 15 | Nouakchott-Ouest | 556 | 15 947 300 |
| 3 | Agence Nouakchott-Nord 13 | Nouakchott-Nord | 630 | 14 926 700 |
| 4 | Agence Trarza 4 | Trarza | 541 | 14 837 300 |
| 5 | Agence Nouakchott-Nord 2 | Nouakchott-Nord | 574 | 14 198 700 |

> L'agence Dakhlet Nouadhibou 7 génère le plus grand volume malgré un nombre de transactions inférieur → panier moyen plus élevé.

---

### Q6 · Opportunités de croissance

Wilayas avec le ratio transactions/utilisateurs le plus bas (sous la moyenne nationale) :

| Wilaya | Utilisateurs | Transactions | Tx/User | Opportunité |
|---|---|---|---|---|
| Guidimaka | 198 | 1 660 | 8,38 | Potentiel modéré |
| Gorgol | 319 | 2 742 | 8,60 | Potentiel modéré |
| Tiris Zemmour | 513 | 4 609 | 8,98 | Potentiel modéré |
| Inchiri | 104 | 947 | 9,11 | Potentiel modéré |
| Adrar | 251 | 2 379 | 9,48 | Potentiel modéré |

> Ces wilayas ont des utilisateurs enregistrés mais une faible activité transactionnelle → campagnes d'activation ciblées recommandées.

---

## Section 3 — Analyse Utilisateurs

### Q7 · Nouveaux utilisateurs ce mois (Décembre 2024)

| Mois | Nouveaux utilisateurs |
|---|---|
| Décembre 2024 | **272** |

> En comparaison, janvier 2024 avait enregistré 767 inscriptions. L'acquisition ralentit en fin d'année.

---

### Q8 · Taux de rétention mensuel

| Mois | Utilisateurs actifs | Retenus du mois précédent | Taux de rétention |
|---|---|---|---|
| Janvier 2024 | 767 | — | — |
| Février | 700 | 73 | 10,4 % |
| Mars | 737 | 60 | 8,1 % |
| Avril | 704 | 75 | 10,7 % |
| Mai | 739 | 69 | 9,3 % |
| Juin | 732 | 78 | 10,7 % |
| Juillet | 710 | 70 | 9,9 % |
| Août | 703 | 61 | 8,7 % |
| Septembre | 703 | 57 | 8,1 % |
| Octobre | 733 | 63 | 8,6 % |
| Novembre | 689 | 73 | 10,6 % |
| **Décembre** | 722 | 78 | **10,8 %** |

> **Taux de rétention moyen : ~9,6 %**. Moins de 1 utilisateur sur 10 revient d'un mois à l'autre — l'engagement long terme est le principal levier d'amélioration.

---

### Q9 · Utilisateurs ayant complété leur KYC

> La colonne `kyc_level` est vide à 100 % dans les données sources (`stg_users.csv`). Résultats basés sur le statut du compte comme indicateur proxy :

| Statut compte | Nb utilisateurs | % |
|---|---|---|
| **ACTIVE** | 8 521 | 85,2 % |
| PENDING_KYC | 542 | 5,4 % |
| INACTIVE | 451 | 4,5 % |
| SUSPENDED | 284 | 2,8 % |
| BLOCKED | 202 | 2,0 % |

> 542 utilisateurs (5,4 %) sont en attente de KYC. Les 85,2 % ACTIVE sont le résultat attendu. À compléter dès que la donnée `kyc_level` sera disponible.

---

## Section 4 — Analyse Transactions

### Q10 · Répartition par type de transaction

| Type | Libellé | Nb transactions | Volume (MRU) | % |
|---|---|---|---|---|
| TRF | Transfert | 29 216 | 150 173 400 | 29,7 % |
| DEP | Dépôt | 22 316 | 748 127 200 | 22,7 % |
| WIT | Retrait | 17 750 | 102 112 450 | 18,0 % |
| PAY | Paiement marchand | 17 362 | 309 838 800 | 17,6 % |
| BIL | Paiement facture | 4 705 | 117 160 400 | 4,8 % |
| AIR | Airtime | 4 031 | 9 625 000 | 4,1 % |
| SAL | Salaire | 2 154 | 596 905 000 | 2,2 % |
| REV | Remboursement | 917 | 23 599 450 | 0,9 % |

> Les **Dépôts** génèrent le volume financier le plus élevé malgré être en 2e position en nombre. Les **Salaires** (2,2 % des tx) représentent un volume colossal de 597 M MRU.

---

### Q11 · Heures de pointe (Top 5)

| Rang | Heure | Nb transactions |
|---|---|---|
| 1 | **09h** | 8 990 |
| 2 | 10h | 8 817 |
| 3 | 17h | 8 158 |
| 4 | 11h | 8 008 |
| 5 | 16h | 7 855 |

> Deux pics d'activité : **matin (9h–11h)** et **fin d'après-midi (16h–17h)**. Dimensionner l'infrastructure en conséquence.

---

### Q12 · Principaux motifs d'échec

| Motif | Nb échecs | % |
|---|---|---|
| INSUFFICIENT_BALANCE | 27 432 | 83,9 % |
| INSUF_BAL *(doublon libellé)* | 1 888 | 5,8 % |
| LIMIT_DAY | 689 | 2,1 % |
| WRONG_PIN | 467 | 1,4 % |
| LIMIT_MTH | 372 | 1,1 % |

> **Note qualité :** `INSUFFICIENT_BALANCE` et `INSUF_BAL` désignent le même motif avec deux libellés différents → à normaliser dans le pipeline ETL. Combinés, ils représentent **~89,7 %** des échecs.
>
> **Solde insuffisant est de loin la première cause d'échec.** Actions possibles : notifications de solde bas, crédit micro-paiement.

---

## Section 5 — Analyse Marchands

### Q13 · Catégories de marchands avec le plus de transactions

| Rang | Catégorie | Nb transactions | Volume (MRU) | % tx |
|---|---|---|---|---|
| 1 | **Alimentation** | 4 988 | 13 136 050 | 28,7 % |
| 2 | Restauration | 2 369 | 6 202 100 | 13,6 % |
| 3 | Télécommunications | 1 891 | 10 011 050 | 10,9 % |
| 4 | Transport | 1 584 | 2 409 400 | 9,1 % |
| 5 | Carburant | 1 447 | 15 031 900 | 8,3 % |
| 6 | Habillement | 1 414 | 22 482 600 | 8,1 % |
| 7 | Santé | 956 | 25 513 400 | 5,5 % |
| 8 | Services | 719 | 7 149 000 | 4,1 % |
| 9 | Éducation | 601 | 30 992 000 | 3,5 % |
| 10 | Électronique | 493 | 50 158 000 | 2,8 % |
| 11 | BTP | 329 | 92 443 000 | 1,9 % |
| 12 | Autre (AUT) | 303 | 8 182 300 | 1,7 % |
| 13 | Hôtellerie (HTL) | 268 | 26 128 000 | 1,5 % |

> L'**Alimentation** domine en volume de transactions mais le **BTP** génère le plus grand volume financier par transaction (voir Q14).

---

### Q14 · Panier moyen par catégorie

| Rang | Catégorie | Nb transactions | Panier moyen (MRU) | Min | Max |
|---|---|---|---|---|---|
| 1 | **BTP** | 12 | 154 750 | 24 000 | 293 000 |
| 2 | Hôtellerie | 42 | 72 881 | 39 000 | 140 000 |
| 3 | Électronique | 63 | 61 333 | 10 000 | 194 000 |
| 4 | Éducation | 95 | 48 126 | 11 000 | 99 000 |
| 5 | Autre (AUT) | 108 | 28 833 | 4 200 | 46 000 |
| 6 | Santé | 256 | 22 120 | 1 500 | 48 000 |
| 7 | Habillement | 504 | 13 364 | 2 300 | 30 000 |
| 8 | Carburant | 614 | 9 310 | 1 100 | 20 000 |
| 9 | Services | 360 | 8 755 | 1 200 | 19 000 |
| 10 | Télécom | 984 | 4 754 | 500 | 10 000 |
| 11 | Alimentation | 3 415 | 2 473 | 200 | 5 000 |
| 12 | Restauration | 1 519 | 2 352 | 350 | 4 900 |
| 13 | Transport | 1 128 | 1 441 | 250 | 3 000 |

> Le **BTP** a le panier le plus élevé (154 750 MRU) mais très peu de transactions (12). Les catégories **Alimentation** et **Restauration** ont un faible panier mais un très fort volume de passages.

---

### Q15 · Marchands actifs vs inactifs

| Statut | Nb marchands | % |
|---|---|---|
| **ACTIVE** | 435 | 87,0 % |
| INACTIVE | 65 | 13,0 % |
| **Total** | **500** | 100 % |

> 65 marchands (13 %) sont inactifs dans le référentiel. À vérifier : sont-ils aussi inactifs transactionnellement ? Action commerciale possible pour réactiver.

---

## Résumé Exécutif

| KPI | Valeur |
|---|---|
| Total transactions | 100 000 |
| Volume total (hors CONFLICT) | ~2 090 M MRU |
| Taux de succès | 67,3 % |
| Frais collectés | 10,7 M MRU |
| Wilaya n°1 | Nouakchott-Ouest (538 M MRU) |
| Agence n°1 | Agence Dakhlet Nouadhibou 7 (16,6 M MRU) |
| Heure de pointe | 9h (8 990 tx) |
| Type dominant | Transfert (29,7 % des tx) |
| Principale cause d'échec | Solde insuffisant (~89,7 %) |
| Catégorie marchands n°1 | Alimentation (28,7 % des paiements) |
| Marchands actifs | 87 % (435/500) |
