# Gestion de projet TaskFlow

> Document de référence pour la gestion des trois dépôts TaskFlow via GitHub Projects.
> Emplacement recommandé : `taskflow-deploy/docs/02-gestion-de-projet/PROJECT_MANAGEMENT.md`
> Dernière mise à jour : 5 août 2026, après la session 4

Ce document a deux parties indépendantes.

La **partie 1** est l'aide-mémoire opérationnel. C'est celle à ouvrir après une pause,
quand il faut retrouver le geste juste sans tout relire.

La **partie 2** est le manuel de reproduction. C'est celle à suivre pour monter la
même configuration sur un projet neuf, quel qu'il soit.

---

# Sommaire

**Partie 1 : aide-mémoire opérationnel**

1. [Vocabulaire](#1-vocabulaire)
2. [Le cycle de vie d'une issue](#2-le-cycle-de-vie-dune-issue)
3. [Ce qui ferme une issue](#3-ce-qui-ferme-une-issue)
4. [Procédure Git complète](#4-procédure-git-complète)
5. [Le workflow auto-add et sa bascule](#5-le-workflow-auto-add-et-sa-bascule)
6. [Cas particuliers](#6-cas-particuliers)
7. [Versionner une livraison](#7-versionner-une-livraison)
8. [Les vues et à quoi elles servent](#8-les-vues-et-à-quoi-elles-servent)

**Partie 2 : manuel de reproduction**

9. [Vue d'ensemble de la configuration cible](#9-vue-densemble-de-la-configuration-cible)
10. [Créer et configurer le Project](#10-créer-et-configurer-le-project)
11. [Configurer les champs](#11-configurer-les-champs)
12. [Configurer les workflows intégrés](#12-configurer-les-workflows-intégrés)
13. [Créer les vues](#13-créer-les-vues)
14. [Configurer les dépôts](#14-configurer-les-dépôts)
15. [Les templates](#15-les-templates)
16. [Limites de plan et impossibilités](#16-limites-de-plan-et-impossibilités)
17. [Ce qui a été écarté et pourquoi](#17-ce-qui-a-été-écarté-et-pourquoi)

---

---

# PARTIE 1 : AIDE-MÉMOIRE OPÉRATIONNEL

---

## 1. Vocabulaire

Ces mots ne sont pas interchangeables. Les confondre est la première source d'erreur.

| Terme | Où il vit | Ce que c'est |
|-------|-----------|--------------|
| **Issue** | Dans le dépôt | Une fiche de travail. A un numéro unique au dépôt, une URL, un **état** ouvert ou fermé. |
| **Pull request** | Dans le dépôt | Une proposition de fusionner une branche. Partage la numérotation des issues. |
| **Item** | Dans le Project | Une ligne qui pointe vers une issue. Porte les champs Status, Start Date, End Date, Phase. |
| **État** | Dépôt | `open` ou `closed`. Propriété de l'issue. |
| **Statut** | Project | Backlog, In Progress, In Review, Verifying, Done. Propriété de l'item. |
| **Tag** | Dépôt, historique Git | Pointeur immuable vers un commit. Marque une version livrée. |
| **Milestone** | Dépôt | Regroupement d'issues d'un dépôt pour une version. |
| **Phase** | Project | Période de travail transverse aux trois dépôts. |

Points à retenir :

- Le Project ne **contient** pas d'issues, il y **fait référence**. Supprimer le
  Project ne supprime aucune issue.
- Une issue et une pull request ne peuvent jamais porter le même numéro dans un dépôt.
- L'**état** et le **statut** sont deux choses différentes. Sur ce projet, ils sont
  **volontairement désalignés** pendant la phase de vérification (voir section 3).
- Le **tag** et le **milestone** portent le même nom par convention pure. Aucun lien
  technique ne les relie. On ne renseigne jamais un tag sur une issue.
- Le **milestone** appartient à un dépôt, la **phase** appartient au Project.

---

## 2. Le cycle de vie d'une issue

C'est la section la plus importante du document.

```
  ┌──────────┐   manuel    ┌─────────────┐   AUTO      ┌───────────┐
  │ Backlog  │ ──────────► │ In Progress │ ──────────► │ In Review │
  └──────────┘  je crée    └─────────────┘  j'ouvre    └───────────┘
       ▲        la branche         ▲        la PR            │
       │ AUTO                      │                         │ AUTO
       │ création                  │ AUTO                    │ je merge
       │ de l'issue                │ je rouvre               │
       │                           │ l'issue                 ▼
       │                           │                  ┌────────────┐
       │                           └───────────────── │ Verifying  │
       │                             si la vérif      └────────────┘
       │                             échoue                  │
       │                                                     │ manuel
       │                                                     │ vérifié
       │                                                     ▼
       │                                              ┌────────────┐
       │                                              │    Done    │
       │                                              └────────────┘
       │
       └── l'issue est déjà `closed` depuis le merge
```

### Tableau des transitions

| Vers | Déclencheur | Automatique ? | Geste à faire |
|------|-------------|---------------|---------------|
| Backlog | L'issue est ajoutée au Project | **Oui** | Rien |
| In Progress | Je décide de commencer | Non | Déplacer la carte **et renseigner `Start Date`** |
| In Review | Une pull request est liée à l'issue | **Oui** | Rien |
| Verifying | Le merge ferme l'issue, `Item closed` réagit | **Oui** | Rien |
| In Progress | Je rouvre l'issue après un échec de vérification | **Oui** | Rien |
| Done | Vérification en production concluante | Non | Déplacer la carte **et renseigner `End Date`**. Deux passages si l'issue est encore ouverte (rattrapage) |

Deux transitions manuelles seulement : l'entrée en `In Progress` et le passage
en `Done`. Ce sont exactement les deux moments où une date doit être saisie.

### Ce que signifie chaque statut

**Backlog.** Identifié, décrit, pas commencé.

**In Progress.** La branche existe, le travail est en cours.

**In Review.** Le code est écrit et soumis. On attend le CI. Rien ne dépend plus de moi.

**Verifying.** Mergé et déployé. **L'issue est déjà fermée dans le dépôt.** On attend
la confirmation que ça fonctionne réellement en production.

**Done.** Vérifié. L'issue était déjà fermée, rien ne change dans le dépôt.

### Les deux gestes à ne jamais oublier

1. Quand je passe une carte en **In Progress**, je renseigne `Start Date`.
2. Quand je passe une carte en **Done**, je renseigne `End Date`.

Ces deux champs alimentent le Gantt de la vue Roadmap. Personne ne les remplira
à ma place : ils sont manuels par choix assumé (voir section 17). Les descriptions
des options de statut le rappellent au moment exact du déplacement de carte.

---

## 3. Ce qui ferme une issue

Cette section remplace l'ancienne opposition entre `Refs` et `Closes`, qui
reposait sur une compréhension erronée du mécanisme.

### Le fait établi

**Le bouton `Create a branch` de la section Development d'une issue crée un lien
de fermeture.** Toute pull request issue de cette branche fermera l'issue au
merge, **quel que soit le mot-clé** écrit dans sa description. `Refs #42` et
`Closes #42` produisent exactement le même résultat.

C'est visible avant même le merge : la timeline de l'issue affiche « linked a
pull request that will close this issue », et l'encadré Development de la pull
request annonce « Successfully merging this pull request may close these issues ».

### La conséquence

L'issue passe à `closed` au merge. Le workflow `Item closed` réagit et pose
`Verifying`. La carte avance automatiquement, ce qui est le comportement voulu.

En contrepartie, **l'état `closed` signifie « mergé » et non « terminé »** sur ce
projet. Une issue en attente de vérification n'apparaît plus dans la liste des
issues ouvertes du dépôt. Le travail restant n'est visible que depuis le Project.

C'est un arbitrage assumé, défendable sur un projet en déploiement continu sans
préproduction : le merge est la fin du travail de développement, et `Verifying`
couvre une phase où plus aucun code n'est écrit.

### Si la vérification échoue

Rouvrir l'issue par le bouton `Reopen issue`. Le workflow `Item reopened` ramène
la carte en `In Progress`. Voir section 6 pour la suite.

### Le réglage qui contrôle tout cela

`Settings` > `General` > bloc `Issues` > **`Auto-close issues with merged linked
pull requests`**, coché.

Le décocher inverse le comportement : l'issue reste ouverte au merge, la carte
reste en `In Review`, et il faut poser `Verifying` à la main. Attention, ce
réglage neutralise aussi les mots-clés `Closes`, `Fixes` et `Resolves`, qui
cessent de fonctionner même écrits explicitement.

### Le rebond, et quand il se produit

Poser `Done` sur une issue **encore ouverte** provoque un rebond. La séquence est
la suivante : `Auto-close issue` ferme l'issue, cette fermeture déclenche
`Item closed`, qui repose `Verifying`. La carte quitte `Done` quelques secondes
après y avoir été placée.

Il suffit de la repasser en `Done` une seconde fois. Ce second passage tient
définitivement, `Item closed` réagissant à l'événement de fermeture et non à
l'état fermé. L'issue étant déjà close, aucun nouvel événement n'est émis.

**Le critère est l'état de l'issue au moment du geste, pas le contexte.** Une
issue déjà fermée ne rebondit jamais, quelle qu'en soit la raison. C'est ce qui
explique que le rattrapage d'un historique déjà fermé, comme les 25 issues de
`taskflow-api` en session 4, ne demande qu'un seul passage, là où des issues
créées ouvertes en demandent deux.

Le flux normal n'est donc jamais concerné : l'issue y est fermée depuis le merge.

Constaté sur les 22 items de la session 2, les 2 de la session 3 et les 6 issues
parents de la session 4.
**Contrôle de fin de session : la colonne `Verifying` du Kanban doit être à 0.**

Décocher `Auto-close issues with merged linked pull requests` supprimerait le
rebond, en supprimant la fermeture qui le cause, mais casserait tout le reste :
l'issue resterait ouverte au merge, la carte resterait en `In Review`, et il
faudrait poser `Verifying` à la main. Le garder coché et faire deux passages est
le meilleur arbitrage.

---

## 4. Procédure Git complète

### Étape 1 : créer l'issue

Onglet Issues du dépôt, bouton `New issue`. Choisir le template adapté parmi les
cinq. Le titre est pré-rempli avec le préfixe du dépôt, le label est appliqué
automatiquement.

Remplir le résumé, les critères d'acceptation, les notes techniques.
Renseigner le milestone si la version de livraison est connue.

Vérifier que l'issue apparaît dans le Project. Si l'auto-add ne pointe pas sur ce
dépôt, l'ajouter à la main : barre latérale droite, section `Projects`,
sélectionner TaskFlow.

### Étape 2 : créer la branche

**Depuis la page de l'issue**, barre latérale droite, section `Development`, lien
`Create a branch`. GitHub propose un nom, le renommer selon la convention :

```
feat/42-task-assignee-select
fix/42-nginx-critical-cve
refactor/42-extract-task-table-component
chore/42-upgrade-node-24
docs/42-update-readme
```

Format : `<type>/<numéro-issue>-<description-courte-en-anglais>`

Types : `feat`, `fix`, `refactor`, `chore`, `docs`.

Cette méthode associe formellement la branche à l'issue et crée le lien de
fermeture décrit en section 3.

### Étape 3 : récupérer la branche en local

```powershell
git checkout main
git pull origin main
git fetch origin
git checkout feat/42-task-assignee-select
```

`git fetch origin` récupère la référence de la branche créée sur GitHub sans la
fusionner. Sans lui, le `checkout` échouerait, la branche n'existant pas localement.

### Étape 4 : déplacer la carte

Dans le Project, faire glisser la carte de `Backlog` vers **In Progress**.
Renseigner `Start Date` avec la date du jour.

### Étape 5 : committer

Format Conventional Commits, en anglais, à l'impératif, sans majuscule initiale,
sans point final :

```
feat: add task assignee select with project members
fix: prevent scroll overflow on task detail dialog
refactor: extract TaskTableComponent from ProjectDetailComponent
chore: upgrade nginx base image to 1.27-alpine
docs: update README with empty state screenshots
```

**Ne jamais faire de `git pull` sans rebase sur une branche partagée.** Un pull
en mode merge produit un commit de merge qui ne porte aucun travail, pollue
l'historique et ne peut être rattaché à aucune issue. Deux commits de ce type
subsistent dans le portfolio, `0b7c521` sur `taskflow-api` et `3aa8ee0` sur
`taskflow-deploy`, tous deux antérieurs à la protection de `main`.

### Étape 6 : pousser et ouvrir la pull request

```powershell
git push -u origin feat/42-task-assignee-select
```

`-u` est l'abréviation de `--set-upstream`. Il inscrit dans `.git/config` la
correspondance entre la branche locale et la branche distante. Les `git push` et
`git pull` suivants n'auront plus besoin d'arguments, et `git status` pourra
indiquer l'avance ou le retard sur la distante.

Ouvrir la pull request sur GitHub. La description est pré-remplie par le template.
Compléter le numéro d'issue après `Refs #`, lister les changements.

**Le titre de la pull request doit respecter Conventional Commits**, puisqu'il
devient le message du commit unique sur `main` après le squash merge.

**Ne pas cocher les cases à ce stade.** Les laisser en `- [ ]`.

La carte passe automatiquement en **In Review**.

### Étape 7 : attendre le CI

Ne jamais merger sur un CI rouge. Quand chaque contrôle passe, cocher les cases
correspondantes directement sur la page de la pull request, par clic.

Sur `taskflow-api`, attention : Checkstyle et OWASP sont en `continue-on-error`.
Un CI vert ne dit rien de leur contenu. Ouvrir leurs rapports avant de cocher.

### Étape 8 : merger

**Squash merge**, seule méthode autorisée par les réglages du dépôt et par le
ruleset. Le message est pré-rempli avec le titre de la pull request.

La carte passe automatiquement en **Verifying**. L'issue se ferme dans le dépôt.
La branche distante est supprimée automatiquement.

### Étape 9 : vérifier en production

Attendre la fin du pipeline CD. Ouvrir l'application déployée et vérifier
concrètement le comportement attendu.

Si ça ne fonctionne pas, rouvrir l'issue et reprendre à l'étape 2 avec une
nouvelle branche (voir section 6).

### Étape 10 : clore

Déplacer la carte vers **Done**. Renseigner `End Date`.
L'issue est déjà fermée, rien ne change dans le dépôt.

### Étape 11 : nettoyer

```powershell
git checkout main
git pull origin main
git fetch --prune origin
git branch -d feat/42-task-assignee-select
```

Il n'y a **pas** de `git push origin --delete` : la branche distante est supprimée
automatiquement au merge. `--prune` supprime les références locales pointant vers
des branches distantes disparues, sans quoi `git branch -a` afficherait
indéfiniment des branches fantômes.

`git branch -d` refuse de supprimer une branche non fusionnée, ce qui est une
sécurité. Ne jamais utiliser `-D` sans savoir précisément pourquoi.

---

## 5. Le workflow auto-add et sa bascule

Le plan GitHub Free n'autorise **qu'un seul** workflow auto-add. Il ne peut donc
couvrir qu'un dépôt à la fois.

### Stratégie retenue

Le workflow suit le dépôt sur lequel je travaille. Quand j'attaque un chantier sur
un autre dépôt, je le rebascule.

### Comment le rebasculer

1. Ouvrir le Project.
2. Menu en haut à droite (icône à trois points), puis **Workflows**.
3. Sélectionner **Auto-add to project** dans la colonne de gauche.
4. Cliquer **Edit** en haut à droite.
5. Changer le dépôt dans le sélecteur du bloc du haut.
6. Vérifier que le filtre est `is:issue`.
7. Cliquer **Save workflow** en haut à droite.

### Point critique

L'auto-add ne capte que les items **créés après** son activation. Il faut donc
**toujours** le configurer avant de créer une série d'issues, jamais après.

Pour les dépôts non couverts, ajouter l'issue à la main : barre latérale droite de
l'issue, section `Projects`, sélectionner TaskFlow. C'est un clic, et l'ajout
manuel n'est jamais limité.

### Filtre

`is:issue` uniquement, sans `is:open`. Le filtre n'est évalué qu'à la création de
l'issue, moment où elle est toujours ouverte : `is:open` serait une condition
inerte, et un filtre inerte laisse croire à une intention qui n'existe pas.

`is:issue` en revanche est indispensable. Sans lui, chaque pull request créerait
son propre item, la Roadmap afficherait deux barres pour un même travail, et le
workflow `Pull request merged` cesserait d'être inoffensif.

---

## 6. Cas particuliers

### Plusieurs pull requests pour une seule issue

C'est normal dès qu'il y a de l'exploration, ou quand le déploiement est nécessaire
pour tester (cas des CVE Docker : Trivy ne tourne que dans le pipeline CD, qui ne se
déclenche que sur `main`).

Marche à suivre après un échec de vérification :

1. Rouvrir l'issue par `Reopen issue`. La carte revient en `In Progress`
   automatiquement.
2. **Ne pas toucher à `Start Date`.** Il marque le début du travail sur l'issue,
   pas le début de la tentative en cours. Le modifier effacerait la durée réelle,
   qui est justement ce que raconte une issue à plusieurs tentatives.
3. Créer une nouvelle branche depuis le bouton `Create a branch` de la même issue,
   avec un nom **descriptif de la tentative** et non un numéro incrémental.

```
fix/42-nginx-stable
fix/42-nginx-1.26-alpine
fix/42-apk-upgrade-openssl
```

Toutes portent le numéro d'issue. La carte fait des allers-retours entre
`In Progress`, `In Review` et `Verifying`. C'est attendu, et l'historique le
raconte fidèlement.

Chaque merge referme l'issue, donc chaque échec impose une réouverture manuelle.

### Réutiliser une branche déjà mergée

À ne pas faire. Recréer une branche sous un nom déjà utilisé rend l'historique
confus : deux pull requests distinctes semblent venir de la même branche. La
suppression automatique des branches au merge rend d'ailleurs la question caduque.

### Continuer à travailler sur une pull request ouverte

Tant qu'elle n'est pas mergée, il suffit de pousser de nouveaux commits sur la
branche. La pull request se met à jour, le CI se relance. **Ne pas ouvrir une
seconde pull request.**

### Une issue qui s'avère plus grosse que prévu

La convertir en issue parent et créer des sous-issues. Depuis la page de l'issue,
section `Sub-issues`, bouton `Create sub-issue`.

Le workflow **Auto-add sub-issues to project** les ajoutera automatiquement.

**Un parent ne porte ni section `Commits` ni bloc `Related PRs`.** Il regroupe, il
ne décrit pas de code. Le travail, les commits et les pull requests appartiennent
aux enfants. Porter la même information à deux niveaux finit toujours par diverger.

### Travail sur plusieurs dépôts en parallèle

Chaque dépôt a ses propres issues. Les rattacher à la **même phase** dans le
Project pour qu'elles apparaissent groupées.

### Rattraper un historique déjà sur main

Cas des sessions 2, 3 et 4 : le travail existe, il est mergé depuis des mois, et
il s'agit de lui donner rétroactivement une trace de gestion de projet.

Ces issues **ne suivent pas le flux**. Il n'y a ni branche ni pull request à
créer, puisque le code est déjà sur `main`. Elles sont créées, renseignées en
dates et en phase, puis passées directement en `Done`, ce qui déclenche leur
fermeture par `Auto-close issue`.
Ce passage en `Done` doit être fait **deux fois** pour une issue créée ouverte, le
premier étant annulé par le rebond décrit en section 3. Une issue déjà fermée,
comme les 25 historiques de `taskflow-api`, n'y est pas soumise.

C'est une dérogation assumée, limitée au rattrapage. Elle doit être écrite dans
l'état du projet, faute de quoi un lecteur y verrait un flux bâclé plutôt qu'un
historique reconstruit.

Sur le rattachement des pull requests, deux formes coexistent et il faut choisir
en connaissance de cause. Le lien natif de la section `Development` est visible
dans la barre latérale de l'issue et dans la colonne `Linked pull requests` du
Project, mais il déclenche `Pull request linked to issue`, qui pousse la carte en
`In Review` y compris sur une issue fermée : il faut ensuite la remettre en
`Done`, en un seul passage puisque l'issue est déjà close. Le bloc textuel, lui,
ne déclenche rien mais reste invisible depuis le Project. Sur TaskFlow, **les
deux sont posés** : le lien natif pour la lisibilité dans la vue `All items`, le
bloc textuel pour la lisibilité dans le corps de l'issue.

Format du bloc, uniformisé sur les trois dépôts :

```markdown
## Related PRs
- PR #4
- PR #5

## Commits
- 6da73d9 - fix: switch to jammy base image to resolve CRITICAL CVE (PR #4)
```

Section de niveau 2 placée entre `Summary` et `Commits`, une ligne par pull
request, et rappel `(PR #N)` en fin de la ligne de commit correspondante. GitHub
transforme `#N` en lien enrichi affichant le titre de la pull request. La forme
en ligne `Related PRs: #1, #2` a été abandonnée : elle se noie dans le corps et
n'apparaît pas dans le sommaire automatique de l'issue.

**Créer un lien parent-enfant, en revanche, ne déclenche rien.** Vérifié en
session 4 sur vingt-cinq rattachements portant tous sur des issues fermées en
statut `Done` : aucune carte n'a bougé. Un rattrapage peut donc construire sa
hiérarchie sans précaution particulière. **Changer le milestone d'une issue est
également sans effet** sur son item.

---

## 7. Versionner une livraison

Convention SemVer : `MAJEUR.MINEUR.CORRECTIF`.

| Position | Quand l'incrémenter | Exemple | Commit type |
|----------|---------------------|---------|-------------|
| **Correctif** | Correction de bug, sans nouveauté | `1.0.0` → `1.0.1` | `fix:` |
| **Mineur** | Nouvelle fonctionnalité compatible | `1.0.1` → `1.1.0` | `feat:` |
| **Majeur** | Rupture de compatibilité | `1.1.0` → `2.0.0` | `BREAKING CHANGE` |

Les types `refactor`, `chore` et `docs` ne font pas bouger la version. Ce lien est
inscrit dans les descriptions des labels `feat` et `fix`.

Les positions à droite repartent à zéro quand une position à gauche est incrémentée.

Chaque dépôt a **sa propre version**. `taskflow-api` en `v1.3.0` et `taskflow-ui`
en `v1.1.2` est parfaitement normal.

### Poser un tag

```powershell
git checkout main
git pull origin main
git config user.email
git tag -a v1.1.0 -m "Add task assignee selection"
git push origin v1.1.0
git cat-file -p v1.1.0
```

`-a` crée un tag annoté, avec auteur, date et message, contrairement à un tag léger
qui n'est qu'un pointeur nu. Le `push` est obligatoire, les tags ne partent pas
avec un push de branche.

Le `git pull` avant est essentiel : sans lui, on tague un commit antérieur au
dernier travail.

Le `git config user.email` intercalé n'est pas décoratif. **L'attribution GitHub
d'un tag dépend de l'adresse e-mail inscrite dans la configuration Git au moment
de sa création**, pas du compte connecté à l'interface. Une adresse rattachée à
un autre compte attribuera le tag à ce compte, et l'inscrira publiquement dans
l'objet tag. Le `git cat-file` final permet de vérifier la ligne `tagger`.

Corriger un tag mal attribué :

```powershell
git push origin --delete v1.1.0
git tag -d v1.1.0
# corriger la configuration, puis recréer
```

### À quoi servent les tags

Revenir à un état livré par `git checkout v1.0.0`. Comparer deux versions par
`git diff v1.0.0 v1.1.0`. Ancrer une image Docker sur une version lisible.

### Lien avec les milestones

Un milestone porte le nom d'une version : `v1.0.0`, `v1.1.0`. Il regroupe les issues
d'**un seul dépôt** livrées dans cette version. Il se ferme quand la version est
livrée, pas quand une date arrive, donc il n'a pas de date d'échéance.

Les milestones ne servent **pas** à représenter les phases de travail. Ce rôle
appartient au champ `Phase` (voir section 11).

**Une issue ne porte qu'un seul milestone.** Réaffecter un lot d'issues à un
milestone de version vide donc les milestones d'origine. Si ceux-ci portaient une
information de découpage, elle doit être reportée ailleurs **avant** l'opération.
Sur `taskflow-api`, les six milestones de sprint ont été vidés au profit de
`v1.0.0` en session 4 ; le champ `Phase` en porte une partie et le découpage en
six issues parents en porte le reste, ce qui est la vraie raison pour laquelle ces
parents épousent exactement les six anciens sprints.

### Releases

Un tag n'est pas une release. GitHub permet de publier une release à partir d'un
tag, avec un titre, des notes de version et des binaires. Non utilisé pour
l'instant.

---

## 8. Les vues et à quoi elles servent

| Vue | Type | À quoi elle sert |
|-----|------|------------------|
| **Kanban** | Board | Le travail quotidien. Où en est chaque chose. |
| **Roadmap overview** | Roadmap | Le Gantt de présentation. Seulement les issues parents. |
| **Roadmap detail** | Roadmap | Le Gantt fin, sous-issues comprises. |
| **Backlog** | Table | La préparation. Écrire les issues à venir. |
| **By repository** | Board | Matrice dépôts en lignes, statuts en colonnes. |
| **By phase** | Table | La lecture chronologique, tous dépôts confondus. |
| **All items** | Table | L'administration. Éditer les dates, corriger en masse. |

Règle simple : le **Board** pour travailler, la **Roadmap** pour montrer, la
**Table** pour administrer.

La Table est la seule vue où l'édition est efficace, parce que chaque champ y est
une colonne. C'est là qu'on saisit les dates et les phases en série.

**La Table est aussi la seule vue supportant l'affichage hiérarchique des
sous-issues.** Ni le Board ni la Roadmap ne le proposent. D'où la séparation
entre `Roadmap overview` et `Roadmap detail`, qui simule la hiérarchie par un
filtre.

**`By phase` est une Table et non un Board**, contrairement à ce que suggérerait
un `Column by: Phase`. Un Board dont le champ de colonne est une itération
n'expose qu'une fenêtre glissante de quatre valeurs, l'itération courante et les
trois précédentes, ce qui rend invisible tout historique plus ancien. Voir
section 13.

`By repository` est la vue la plus parlante pour une présentation : elle montre en
une image que trois dépôts sont pilotés depuis un point unique.

Le zoom de `Roadmap overview` est réglé sur `Year` et non `Month`, pour donner
assez de recul à une capture couvrant plusieurs mois. `Month` reste préférable
pour lire le détail d'une période courte.

---

---

# PARTIE 2 : MANUEL DE REPRODUCTION

Cette partie décrit comment monter la configuration complète sur un projet neuf.
Suivre les sections dans l'ordre.

**Ordre imposé par trois contraintes.** Les champs avant les vues, une vue
affichant des champs qui doivent exister. Les labels avant les templates, un
template déclarant `labels: feat` n'appliquant rien si le label n'existe pas.
La protection de `main` en dernier, les étapes précédentes écrivant sur `main`.

---

## 9. Vue d'ensemble de la configuration cible

Un GitHub Project unique, rattaché à un compte utilisateur, couvrant plusieurs dépôts.

**Champs personnalisés** : `Start Date` (Date), `End Date` (Date), `Phase`
(Iteration). Le champ `Status` natif est reconfiguré à cinq options avec descriptions.

**Workflows intégrés** : huit activés, trois désactivés.

**Vues** : sept, réparties entre Board, Roadmap et Table.

**Dépôts** : chacun avec ses huit labels, son milestone de version, son tag, ses
six templates, ses réglages de merge et son ruleset.

**Aucun secret, aucun PAT, aucun workflow GitHub Actions dédié à la gouvernance.**
Tout repose sur les automatisations natives de GitHub.

---

## 10. Créer et configurer le Project

### Créer le Project

1. Profil GitHub, onglet **Projects**.
2. Bouton **New project**.
3. Choisir le modèle **Table**, le plus neutre.
4. Nommer le projet.
5. Bouton **Create project**.

### Récupérer les identifiants en ligne de commande

Prérequis : GitHub CLI installé et authentifié avec le scope `read:project`.

```powershell
gh auth status
gh project list --owner <mon-login>
```

Si `read:project` manque dans les scopes affichés, et seulement dans ce cas :

```powershell
gh auth refresh -s read:project
```

Pour inspecter les champs à tout moment :

```powershell
gh project field-list <numéro> --owner <mon-login> --format json
```

Cette commande donne les identifiants des champs et, pour les single select, les
identifiants des options. **Elle ne donne ni les couleurs, ni les descriptions,
ni le détail des itérations d'un champ Iteration.** Pour ces dernières, il faut
passer par l'API GraphQL :

```powershell
gh api graphql -f query='
{
  node(id: "<identifiant PVT_>") {
    ... on ProjectV2 {
      field(name: "Phase") {
        ... on ProjectV2IterationField {
          id
          name
          configuration {
            iterations { id title startDate duration }
            completedIterations { id title startDate duration }
          }
        }
      }
    }
  }
}'
```

GitHub bascule automatiquement une itération dans `completedIterations` dès que sa
date de fin est passée. L'API renvoie `startDate` et `duration`, jamais la date de
fin : ajouter la durée moins un, les bornes étant incluses. Les breaks ne sont pas
exposés, ils ne se vérifient qu'à l'œil.

---

## 11. Configurer les champs

Accès : menu en haut à droite du Project (icône à trois points), puis **Settings**.

### Comprendre ce qui existe déjà

Treize champs sont créés automatiquement par GitHub et ne sont **pas modifiables** :

`Title`, `Assignees`, `Status`, `Labels`, `Linked pull requests`, `Milestone`,
`Repository`, `Reviewers`, `Parent issue`, `Sub-issues progress`, `Created`,
`Updated`, `Closed`.

Les trois champs de date natifs sont en lecture seule et **ne peuvent pas servir
de bornes dans la vue Roadmap**. Le sélecteur « Date fields » n'accepte que des
champs de type Date créés manuellement. Ils restent utilisables pour le tri et le
filtrage. D'où la nécessité de créer deux champs de date personnalisés.

### Reconfigurer le champ Status

Dans Settings, cliquer sur **Status**. Bouton `Add option` pour ajouter,
poignée à six points pour réordonner par glisser-déposer. Aucun bouton de
sauvegarde, l'édition est immédiate.

| Ordre | Option | Description à saisir |
|-------|--------|----------------------|
| 1 | Backlog | Identified and described, not started. Set automatically when the item enters the project. |
| 2 | In Progress | Branch created, work underway. Set Start Date when moving the card here. |
| 3 | In Review | Pull request open, awaiting CI or review. Set automatically when a pull request is linked. |
| 4 | Verifying | Merged and deployed, awaiting production verification. Move here right after the squash merge. |
| 5 | Done | Verified in production. Set End Date; the issue closes automatically in the repository. |

L'ordre détermine l'ordre des colonnes de toute vue Board groupée par `Status`.
Une colonne `Verifying` placée après `Done` raconterait un cycle de vie faux.

**Les descriptions ne sont pas décoratives.** Elles s'affichent sous les en-têtes
de colonne du Board et dans le sélecteur de statut. Elles suivent toutes le même
moule en deux temps : la condition d'entrée, puis le geste à faire. Les deux gestes
qu'on oublie, `Start Date` et `End Date`, y sont inscrits, ce qui les place sous
les yeux au moment exact du déplacement de carte.

Choisir pour `Verifying` une couleur distincte de `Done` et de `In Review`.

Le statut `Verifying` n'est utile que sur un projet en déploiement continu sans
environnement de préproduction. Avec un environnement de staging, il devient inutile.

### Créer Start Date et End Date

Dans Settings, bouton **New field**.

- Nom : `Start Date`, type : **Date**.
- Nom : `End Date`, type : **Date**.

Ne pas nommer le second `Target Date` : « target » désigne une date **visée** fixée
à l'avance, alors que l'usage ici est de saisir la date **constatée** après coup.

**Ces champs ne se saisissent qu'au sélecteur.** La cellule n'accepte aucune
saisie clavier, et le calendrier s'ouvre sur le mois courant. Pour une saisie en
série sur un historique, trier les items par date croissante et saisir dans cet
ordre : le calendrier conserve le mois affiché d'une cellule à l'autre, ce qui
évite de renaviguer plusieurs mois en arrière à chaque ligne.

Le champ `Phase`, en revanche, est un sélecteur de liste sans contrainte de
navigation : l'ordre de saisie y est indifférent.

### Créer le champ Phase

Dans Settings, bouton **New field**. Nom : `Phase`, type : **Iteration**.

**Ne pas le nommer `Sprint`.** Deux raisons. Ce ne sont pas des sprints Scrum mais
des phases à durée variable. Et le nom du champ détermine la syntaxe de filtrage :
un champ `Phase` se filtre par `phase:@current`.

À la création, GitHub génère trois itérations à partir d'aujourd'hui. Il faut les
reprendre entièrement. **On ne peut pas supprimer la dernière**, un champ Iteration
devant en contenir au moins une : supprimer les deux du bas, puis recycler celle qui
reste en la renommant et en la redatant.

Pour éditer : Settings, cliquer sur le nom du champ.

- Renommer une itération : cliquer sur son nom et taper.
- Changer sa plage : cliquer sur la date, sélectionner le jour de début puis le jour
  de fin, puis **Apply**.
- Ajouter une itération : le bouton **Add iteration** en crée une accolée à la
  dernière, de même durée, sans rien demander. Pour choisir date de début et durée,
  passer par la flèche à droite du bouton ou **More options**.
- Supprimer : icône corbeille à droite de la ligne, puis **Save**.
- Insérer une pause : survoler la ligne de séparation **au-dessus** d'une itération,
  puis **Insert break**. Un break n'est pas une ligne qu'on ajoute, c'est une
  respiration entre deux itérations existantes. Il occupe automatiquement l'espace
  disponible.

Le panneau sépare les itérations en deux onglets, `Active` et `Completed`, selon
que leur date de fin est passée ou non. Une itération créée par erreur peut donc
se trouver dans l'un ou l'autre.

**Les itérations peuvent être créées dans le passé.** C'est ce qui permet de
reconstruire une timeline historique.

GitHub trie les itérations chronologiquement et les réordonne tout seul. Les lignes
sauteront pendant la saisie, c'est normal.

La durée se compte bornes incluses : du 28 au 31 mars fait quatre jours. Une durée
d'un jour est acceptée.

**Attention au bouton `New column` d'une vue Board.** Sur un Board dont le champ de
colonne est ce champ Iteration, ce bouton ne se contente pas d'afficher une colonne
existante : il **crée une itération** dans le champ, donc dans le Project entier,
immédiatement et sans confirmation. Voir section 13.

### Phases variables ou sprints réguliers ?

**Sprints réguliers** (durée fixe) : approche Scrum. La régularité permet de mesurer
une vélocité. Adapté à une équipe à temps plein.

**Phases variables** (durée libre, calées sur le travail réel) : adapté à un projet
mené par intermittence. Des sprints réguliers sur un rythme irrégulier produiraient
des itérations vides qui ne mesurent rien.

Sur TaskFlow, c'est la seconde approche, avec des **breaks** pour matérialiser les
périodes sans activité.

Trois principes de découpage retenus :

- **Un break matérialise une interruption franche**, pas un jour creux au milieu
  d'un chantier continu. Une itération mesure une période de travail, pas une somme
  d'heures. Découper à chaque jour creux reviendrait à faire du pointage horaire.
- **Une phase courte est légitime si elle est vraie.** Une timeline où toutes les
  itérations font deux semaines est immédiatement identifiable comme reconstruite
  après coup. L'irrégularité se lit comme un vrai historique.
- **Une issue à cheval sur deux phases** est rattachée à la phase où se trouve la
  majorité de son travail. Un item ne porte qu'une seule valeur d'itération, mais
  la Roadmap continue d'afficher les vraies dates de chaque barre.

Cas particulier d'un **parent dont les enfants se répartissent à égalité** entre
deux phases : la règle de majorité ne tranche pas. Retenir la phase la plus longue,
et écrire la décision. C'est le cas de l'issue n° 43 de `taskflow-api`, placée en
Phase 6 alors que ses deux enfants sont en Phases 6 et 7.

Nommage : `Phase N - Intitulé transverse court`. Les intitulés ne doivent pas être
spécifiques à un dépôt, puisqu'une phase les couvre tous. Un intitulé à deux volets
est acceptable quand aucun thème commun n'existe réellement : mieux vaut encombrant
et exact qu'élégant et vague.

La phase en cours est la seule dont on fixe la fin à l'avance au lieu de la
constater. Fixer une borne courte et l'étendre au besoin, plutôt qu'ouvrir une
phase de trois mois qui ne mesurerait rien.

### Filtrer par phase

```
phase:@current
phase:@previous
phase:@next
phase:>"Phase 4"
no:phase
```

`no:phase` est le filtre de contrôle : sur un projet entièrement phasé, il doit
renvoyer zéro ligne. C'est aussi le filtre de travail pour une passe de saisie, la
liste se vidant au fur et à mesure des affectations.

---

## 12. Configurer les workflows intégrés

Accès : menu en haut à droite du Project, puis **Workflows**.

Chaque workflow s'affiche comme deux blocs reliés : en haut le déclencheur, en bas
l'action. Le bloc du bas n'est **pas un bouton**, il décrit ce que le workflow fera.
Passer en édition par **Edit** en haut à droite, valider par **Save workflow**.

### Configuration cible

| Workflow | État | Configuration | Rôle |
|----------|------|---------------|------|
| **Auto-add to project** | Activé | Dépôt actif, filtre `is:issue` | Ajoute les nouvelles issues |
| **Auto-add sub-issues to project** | Activé | Aucune | Ajoute les sous-issues |
| **Item added to project** | Activé | `issue, pull request` → **Backlog** | Point d'entrée du kanban |
| **Pull request linked to issue** | Activé | → **In Review** | Le code est soumis |
| **Item closed** | Activé | `issue, pull request` → **Verifying** | Le merge ferme l'issue |
| **Item reopened** | Activé | → **In Progress** | Échec de vérification |
| **Auto-close issue** | Activé | Statut **Done** → ferme l'issue | Filet de sécurité |
| **Pull request merged** | Activé | → Verifying | **Inerte** avec le filtre `is:issue` |
| Auto-archive items | Désactivé | | |
| Code changes requested | Désactivé | | Utile en équipe seulement |
| Code review approved | Désactivé | | **Inerte en solo** |

### Le point à ne pas rater

**Pull request linked to issue** est proposé par défaut sur `In Progress`. **Il faut
le changer en `In Review`.**

Raison : dans ce flux, l'item est déjà passé en `In Progress` manuellement au moment
de la création de la branche. Laisser le workflow sur `In Progress` le rendrait muet,
il ne ferait que réécrire une valeur déjà posée. Sur `In Review`, il porte une
information neuve : le code est écrit et soumis.

### Ce que le sélecteur `issue, pull request` signifie

GitHub ne documente pas ce paramètre. Il filtre le **type d'item du Project** auquel
le workflow réagit. Avec un filtre d'auto-add en `is:issue`, aucune pull request
n'entre dans le Project : la case `pull request` est donc inerte, la laisser cochée
ou non ne change rien.

### Les workflows inertes, et pourquoi

**`Pull request merged`** agit sur l'item de la pull request, pas sur celui de
l'issue liée. Aucune pull request n'étant dans le Project, il ne fait rien. Vérifié
par test : avec la fermeture automatique désactivée sur le dépôt, un merge n'a pas
déplacé la carte.

**`Code review approved`** ne se déclenchera jamais en solo : GitHub interdit
d'approuver sa propre pull request. Le formulaire de revue ne propose que `Comment`.
Utiliser un second compte pour s'auto-approuver serait du théâtre, visible et
contre-productif sur un portfolio.

### Ce qui ne déclenche aucun workflow

**Créer un lien parent-enfant entre deux issues ne déplace aucune carte.**
Vérifié en session 4 sur vingt-cinq rattachements portant tous sur des issues
fermées en statut `Done`. Seul `Auto-add sub-issues to project` réagit, et il se
contente de constater que l'item est déjà dans le Project. C'est la différence
avec la liaison d'une pull request, qui pousse en `In Review` y compris sur une
issue déjà close. Un rattrapage d'historique peut donc construire sa hiérarchie
sans précaution particulière.

**Changer le milestone d'une issue ne déclenche rien non plus.** Une réaffectation
en masse est sans effet sur les statuts des items.

### La paire Item closed et Auto-close issue

**Item closed** synchronise dans le sens dépôt vers Project, **Auto-close issue**
dans le sens Project vers dépôt.

Sur cette configuration, `Item closed` pose `Verifying` et non `Done` : c'est ce qui
fait avancer la carte automatiquement au merge. `Auto-close issue` devient un filet
de sécurité qui ne se déclenche presque jamais, l'issue étant déjà fermée quand on
pose `Done`.

**Cet équilibre suppose que la fermeture automatique du dépôt est active.** Sans
elle, l'issue resterait ouverte au merge et la carte n'avancerait plus seule. Le
rebond décrit en section 3 n'est pas causé par ce réglage mais par le fait de
poser `Done` sur une issue encore ouverte, ce qui n'arrive qu'en rattrapage.

### Attribution des changements automatiques

Quand un workflow intégré modifie quelque chose, l'activité est attribuée à
`@github-project-automation` dans la timeline de l'issue. C'est ce qui permet de
distinguer d'un coup d'œil ce qui a été fait à la main de ce qui a été fait par
l'outil, et de diagnostiquer un comportement inattendu.

### Vérification

Aucune API n'expose les workflows intégrés, ni `gh`. Le relevé est nécessairement
manuel. Le seul test réel est un cycle complet : l'issue doit entrer seule en
`Backlog`, passer seule en `In Review` à l'ouverture de la pull request, et seule
en `Verifying` au merge.

---

## 13. Créer les vues

Le bouton **New view**, à droite des onglets, crée une vue. Une vue est une
configuration **enregistrée** : type de disposition, champs affichés, tri,
regroupement, filtres. Ce n'est pas un mode d'affichage temporaire.

Configuration via le bouton **View** en haut à droite, puis **Save view**. Une
modification non sauvegardée est signalée par un point à côté du nom de l'onglet
et perdue au changement d'onglet ; le bouton **Discard** l'annule explicitement.

Renommer une vue : double-clic sur l'onglet, ou menu de l'onglet puis `Rename view`.
Réordonner les onglets : glisser-déposer. Le premier onglet s'ouvre par défaut.

### Vocabulaire d'interface

- Sur un **Board**, l'option de regroupement en colonnes s'appelle **`Column by`**.
  Sur une **Table** et sur une **Roadmap**, elle s'appelle `Group by`. Ce ne sont
  pas des synonymes interchangeables, ce sont deux libellés selon le type de vue.
- **`Column by` n'accepte que les champs à valeurs énumérées**, donc `Status` et le
  champ Iteration. `Repository` n'y est pas proposé : ses valeurs sont dérivées et
  non une liste d'options.
- `Repository` n'est disponible qu'en **`Swimlanes`** ou en **`Slice by`**.
- **Un Board dont le champ de colonne est une itération n'affiche que l'itération
  courante et les trois qui la précèdent.** Limite non documentée par GitHub,
  constatée le 5 août 2026 sur un champ à huit itérations. Le menu de visibilité
  des colonnes ne propose que ces quatre valeurs ; les autres n'y figurent pas,
  ni cochées ni décochées. Aucun réglage ne contourne cette fenêtre.
- **Un filtre n'agit jamais sur les colonnes d'un Board, seulement sur les
  cartes.** Une colonne dont toutes les cartes sont filtrées reste affichée, vide.
  Inversement, un filtre ne fait pas apparaître une colonne absente.
- **Le bouton tout à droite d'un Board, libellé `New column`, crée une valeur dans
  le champ de colonne.** Sur un champ Iteration, il crée une itération dans le
  Project entier, immédiatement et sans confirmation. Son menu déroulant sert
  aussi à afficher ou masquer des colonnes existantes, mais les deux fonctions
  cohabitent sous le même bouton et la première est destructrice. Pour réparer :
  `Settings` > nom du champ > icône corbeille > `Save`.
- **Sur une Table groupée, `Show hierarchy` ne compte que les items racine.** Les
  sous-issues sont imbriquées sous leur parent et ne comptent plus dans leur
  propre groupe. Un groupe dont tous les items sont des sous-issues disparaît
  entièrement de la vue.

### Vue 1 : Kanban

- Type : **Board**
- `Column by` : `Status`
- Champs visibles : `Labels`, `Repository`, `Phase` au minimum.
  `Sub-issues progress` est vivement recommandé, il affiche une barre de progression
  sur les cartes parents. `Linked pull requests` est utile sur les issues à
  plusieurs tentatives. `Repository` est indispensable dans un Board qui mélange
  les trois dépôts.

### Vue 2 : Roadmap overview

- Type : **Roadmap**
- `Date fields` : `Start Date` en début, `End Date` en fin
- `Zoom level` : `Year`
- Filtre : `no:parent-issue`
- `Sort by` : `Start Date` croissant

Le filtre `no:parent-issue` masque les sous-issues et ne conserve que les issues
parents. Sans lui, la Roadmap affiche parents et enfants au même niveau, sans
indentation, ce qui devient illisible au-delà de quelques dizaines d'items. C'est
cette limitation de GitHub qui impose deux Roadmaps là où une seule suffirait.

Le zoom `Year` donne le recul nécessaire à une capture couvrant plusieurs mois.
`Month` reste préférable pour lire le détail d'une période courte.

### Vue 3 : Roadmap detail

Identique à la précédente, sans le filtre `no:parent-issue`. Dupliquer la vue
précédente par le menu de l'onglet, `Duplicate view`, évite de re-régler dates et zoom.

### Vue 4 : Backlog

- Type : **Table**
- Filtre : `status:Backlog`
- Champs visibles : Title, Labels, Repository, Phase, Milestone

Cette vue peut légitimement être vide tant que tout le travail est terminé.

### Vue 5 : By repository

- Type : **Board**
- `Column by` : `Status`
- `Swimlanes` : `Repository`

Trois bandes horizontales, une par dépôt, chacune traversée par les cinq colonnes
de statut. C'est une matrice à deux entrées, plus riche qu'un simple regroupement.

**Pourquoi Swimlanes et non Slice by.** `Slice by` ajoute un panneau latéral qui
filtre le Board sur un dépôt à la fois : c'est un navigateur, pas un affichage
simultané, et il ferait de cette vue un doublon du Kanban avec un filtre. Swimlanes
montre les trois ensemble, ce qui est l'intention.

Réserve : avec trois swimlanes et cinq colonnes, le défilement devient nécessaire
dès que les colonnes se remplissent. Pour une capture d'écran de portfolio, la
Roadmap reste le meilleur support.

### Vue 6 : By phase

- Type : **Table**
- `Group by` : `Phase`
- `Show hierarchy` : **désactivé**
- `Sort by` : `Repository`, puis `Parent issue`
- Aucun filtre

Un groupe par itération, plus un groupe `No Phase` pour les items non affectés.
C'est la lecture chronologique du portfolio, là où la Roadmap montre des barres et
le Kanban un état. Sur un projet multi-dépôts, c'est la vue qui montre le mieux
qu'une phase est transverse : un même groupe contient des items des trois dépôts.

**Ne pas la construire en Board**, malgré l'apparente évidence d'un
`Column by: Phase`. Un Board n'expose qu'une fenêtre glissante de quatre itérations
autour de la courante, ce qui masque tout historique plus ancien. La version Board
de cette vue, créée en session 2, n'affichait que quatre phases sur huit.

**Et `Show hierarchy` doit rester désactivé.** Avec l'option active, seuls les items
racine sont comptés, et un groupe dont tous les items sont des sous-issues disparaît
entièrement. Sur TaskFlow, cela faisait disparaître la Phase 7 et ramenait le total
affiché de 58 items à 17.

Elle n'a d'intérêt qu'une fois les phases renseignées. Tant que des items sont
sans phase, le groupe `No Phase` concentre l'essentiel et la vue ne raconte rien.
Contrôle : le filtre `no:phase` doit renvoyer zéro ligne.

### Vue 7 : All items

- Type : **Table**
- Aucun filtre
- Champs visibles : tous, y compris `Created` et `Closed` pour contrôle
- Option **Show hierarchy** activée

C'est la vue de saisie en série des dates et des phases. La Table est la seule vue
où l'édition est réellement efficace, chaque champ y étant une colonne.

Avec `Show hierarchy` et sans filtre, les sous-issues y apparaissent deux fois,
imbriquées et à la racine. C'est le prix de la vue d'administration, et il ne se
paie pas sur une Table groupée, où chaque item est rangé dans le groupe de sa
propre valeur.

### Note sur la hiérarchie

**Show hierarchy** n'existe **que sur les vues Table**. Vérifié sur les trois
panneaux de configuration : ni le Board ni la Roadmap ne la proposent. C'est
cohérent avec le fonctionnement d'un Board, qui range chaque carte dans la
colonne de son statut : un parent et son enfant pouvant avoir des statuts
différents, l'imbrication y est impossible par construction. Sur un Board, la
relation n'est visible que par la barre `Sub-issues progress` des parents.

### Nommage

Tous les noms en anglais, comme le reste du portfolio. Un jeu de vues mêlant
français et anglais se remarque immédiatement sur un Project qu'on montre.

---

## 14. Configurer les dépôts

À faire dans **chaque** dépôt du projet.

### Labels

Vocabulaire aligné sur les Conventional Commits, ce qui rend la classification
mécanique. **Huit labels**, identiques sur tous les dépôts, couleurs et
descriptions comprises. Un label qui ne dirait pas la même chose selon le dépôt
cesserait d'être un vocabulaire commun.

| Label | Couleur | Description |
|-------|---------|-------------|
| `feat` | `00a33a` | New feature or user-facing capability. Drives a minor version bump. |
| `fix` | `d93f0b` | Corrects broken behaviour. Drives a patch version bump. |
| `refactor` | `fbca04` | Restructures existing code without changing its behaviour. |
| `chore` | `7e9399` | Maintenance with no impact on the codebase behaviour: dependencies, configuration, tooling. |
| `docs` | `4997f1` | Documentation only: README, Javadoc, JSDoc, OpenAPI, SECURITY. |
| `test` | `7965eb` | Adds or updates automated tests. |
| `security` | `b60205` | Security hardening or vulnerability fix. Combined with feat or fix, never alone. |
| `ci/cd` | `ee9206` | Continuous integration or deployment pipeline. |

Les descriptions suivent un moule : ce que l'issue produit, puis le discriminant qui
la sépare du label le plus proche. Le critère de tri prime sur la définition, parce
que la question posée au moment de créer une issue est « cette case ou la voisine ».

Trois choix encodés dans ces textes. Le lien avec SemVer figure dans `feat` et `fix`
et nulle part ailleurs : un lecteur comprend le schéma de versionnage en survolant
les labels. La frontière `refactor` / `chore` est explicitée des deux côtés,
`refactor` touchant au code de production sans changer son comportement observable,
`chore` n'y touchant pas du tout. `security` porte une contrainte de combinaison,
c'est le seul label transverse du jeu.

Pas de label `perf` : une seule occurrence dans tout le portfolio ne justifie pas
un label.

**Les labels appartiennent aux issues, pas aux pull requests.** L'information est
déjà portée par l'issue liée, le préfixe du titre et le préfixe de la branche. Un
quatrième porteur ne se maintiendrait pas et finirait par diverger.

Création :

```powershell
gh label create feat --repo <owner>/<repo> --color 00a33a --description "New feature or user-facing capability. Drives a minor version bump."
```

Sur un label déjà existant, `gh label create` échoue. Utiliser `gh label edit`, qui
ne modifie que les attributs fournis et laisse les autres intacts.

Le nom `ci/cd` doit être entre guillemets à cause de la barre oblique.

### Supprimer les labels par défaut

GitHub crée neuf labels par défaut sans rapport avec le vocabulaire du projet :
`bug`, `documentation`, `duplicate`, `enhancement`, `good first issue`,
`help wanted`, `invalid`, `question`, `wontfix`.

**Contrôle préalable obligatoire.** Supprimer un label le retire silencieusement de
toutes les issues qui le portent.

```powershell
gh issue list --repo <owner>/<repo> --state all --limit 200 --label "bug,documentation,duplicate,enhancement,good first issue,help wanted,invalid,question,wontfix"
```

Une sortie vide autorise la suppression :

```powershell
$Defaults = @("bug","documentation","duplicate","enhancement","good first issue","help wanted","invalid","question","wontfix")
foreach ($Label in $Defaults) {
    gh label delete $Label --repo <owner>/<repo> --yes
}
```

`--yes` supprime la confirmation interactive, sans laquelle la boucle se bloquerait
à chaque tour. Ne l'employer que sur une liste explicite et vérifiée.

### Note sur PowerShell 5.1 et les guillemets

Un argument contenant à la fois des espaces et des guillemets doubles est démembré
avant d'atteindre `gh`, qui répond « please quote all values that have spaces ».
PowerShell reconstruit une ligne de commande à plat au moment d'appeler un
exécutable externe, et les guillemets internes y sont réinterprétés.

Deux solutions : reformuler pour n'avoir qu'un seul niveau de guillemets, ou
échapper les guillemets internes par `\"`. La première est préférable, la seconde
produit des commandes illisibles. La contrainte disparaît sur PowerShell 7.

### Milestones

Un milestone par version, pas par phase. `gh` n'expose pas de sous-commande dédiée :

```powershell
gh api repos/<owner>/<repo>/milestones -X POST -f title="v1.0.0" -f description="<contenu de la version>"
```

Pas de date d'échéance.

Réaffecter un lot d'issues à un milestone :

```powershell
foreach ($N in 11..35) {
    gh issue edit $N --repo <owner>/<repo> --milestone "v1.0.0"
}
```

`gh issue edit` ne modifie que les attributs passés et laisse tous les autres
intacts. Il ne rouvre pas une issue fermée et ne déclenche aucun workflow du
Project. Relever l'affectation d'origine avant l'opération, une issue ne portant
qu'un seul milestone :

```powershell
gh issue list --repo <owner>/<repo> --state all --limit 200 `
    --json number,milestone --jq '.[] | "\(.number)|\(.milestone.title)"' `
    | Out-File -Encoding utf8 etat-milestones-avant.txt
```

Contrôle après coup, la sortie doit être vide :

```powershell
gh issue list --repo <owner>/<repo> --state all --limit 200 `
    --json number,milestone `
    --jq '.[] | select(.milestone.title != "v1.0.0") | "\(.number)|\(.milestone.title)"'
```

### Réglages de merge

`Settings` > `General` > bloc `Pull Requests`.

| Réglage | Valeur | Pourquoi |
|---------|--------|----------|
| Allow merge commits | **décoché** | Le squash est la seule méthode autorisée |
| Allow squash merging | **coché** | |
| Allow rebase merging | **décoché** | |
| Default commit message | **Titre de la pull request** | Évite la duplication du titre dans le corps du commit |
| Automatically delete head branches | **coché** | Supprime une commande de l'étape de nettoyage |
| Allow auto-merge | **décoché** | Court-circuiterait la lecture des rapports non bloquants |

Décocher les deux méthodes de merge transforme une règle écrite en contrainte
concrète : le bouton de merge n'offre plus qu'une possibilité.

`Default commit message` réglé sur le titre évite le champ `Extended description`
pré-rempli avec le titre recopié, qui produirait un commit portant son sujet deux
fois.

### Fermeture automatique des issues

`Settings` > `General` > bloc `Issues` > `Auto-close issues with merged linked
pull requests`, **coché**. Voir section 3 pour ce que ce réglage détermine.

### Ruleset sur main

`Settings` > `Rules` > `Rulesets` > `New ruleset` > `New branch ruleset`.

Disponible en plan Free **pour les dépôts publics uniquement**.

- Nom : `main`
- `Enforcement status` : **Active**. Un ruleset créé mais `Disabled` ne protège rien.
- `Bypass list` : **vide**. S'y ajouter en tant qu'administrateur viderait la règle
  de son sens.
- `Target branches` : `Add target` > `Include default branch`
- Règles cochées : `Restrict deletions`, `Require a pull request before merging`,
  `Block force pushes`, et `Require status checks to pass` si un pipeline existe
- `Allowed merge methods` : **Squash** seul, par cohérence avec les réglages du dépôt
- `Required approvals` : **0**

**`Required approvals` doit rester à zéro.** L'auto-approbation étant impossible,
toute valeur supérieure bloquerait définitivement tout merge.

Sous `Require status checks to pass`, sélectionner les contrôles par `Add checks`.
La liste ne propose que les contrôles ayant déjà tourné récemment : sur un dépôt
neuf, cette règle ne peut être complétée qu'après la première pull request. **Une
règle cochée sans contrôle sélectionné ne bloque rien**, une liste vide étant
satisfaite d'office.

Deux règles écartées. `Require linear history` interdit les commits de merge, ce que
les réglages du dépôt garantissent déjà, et laisserait sans marge en cas de besoin.
`Require signed commits` demande de générer une clé et de la déclarer, à traiter
séparément.

Vérification :

```powershell
git commit --allow-empty -m "test: verify branch protection"
git push origin main
git reset --hard origin/main
```

Le push doit être rejeté avec `GH013: Repository rule violations found`.

### Identité Git

**L'attribution GitHub d'un commit ou d'un tag dépend de l'adresse e-mail inscrite
dans la configuration Git**, pas du compte connecté à l'interface ni des
identifiants de push.

```powershell
git config --list --show-origin
```

Cette commande révèle toutes les valeurs et leur fichier d'origine, y compris une
surcharge locale dans `.git/config` qui l'emporterait sur la configuration globale.

```powershell
git config --global user.name "<Prénom Nom>"
git config --global user.email "<id>+<login>@users.noreply.github.com"
```

L'adresse `noreply` de GitHub est associée sans ambiguïté au compte et ne divulgue
pas l'adresse personnelle sur un dépôt public. Supprimer toute surcharge locale par
`git config --unset user.email` dans chaque clone.

Sur un poste partagé ou fourni par une école, vérifier avant tout `git tag` ou tout
premier commit. Un tag mal attribué inscrit publiquement l'adresse fautive dans
l'objet tag.

### Relever l'historique d'un dépôt

Pour un rattrapage, le journal des commits sert à vérifier qu'aucun travail n'est
orphelin.

```powershell
git fetch --prune origin
git log origin/main --date=iso-strict --pretty=format:"%H|%ad|%an|%s" | Out-File -Encoding utf8 commits.txt
```

Viser explicitement `origin/main` plutôt que `--all` : sur un dépôt travaillé par
pull requests et squash merges, `--all` peut ressortir les commits d'origine d'une
branche en plus de leur squash si les références locales n'ont pas été nettoyées.
Le `--prune` préalable élimine ce risque.

Contrôle : chaque commit du journal doit se retrouver dans la section `Commits`
d'une issue, à l'exception des commits de merge, qui ne portent aucun travail.

### Vérifier l'absence d'automatisation parasite

```powershell
gh api repos/<owner>/<repo>/contents/.github/workflows --jq ".[].name"
gh secret list --repo <owner>/<repo>
```

---

## 15. Les templates

Les templates transforment une règle écrite dans un document en contrainte concrète
au moment où on crée l'objet.

**Six fichiers par dépôt**, soit dix-huit pour trois dépôts.

```
.github/pull_request_template.md
.github/ISSUE_TEMPLATE/feature.md    → labels: feat
.github/ISSUE_TEMPLATE/bug.md        → labels: fix
.github/ISSUE_TEMPLATE/refactor.md   → labels: refactor
.github/ISSUE_TEMPLATE/chore.md      → labels: chore
.github/ISSUE_TEMPLATE/docs.md       → labels: docs
```

**Cinq templates d'issue, un par label décrivant une nature de travail.** Pas de
template pour `test`, `security` et `ci/cd` : ces labels qualifient un travail
plutôt qu'ils n'en décrivent la nature, ils s'ajoutent en label secondaire sur une
issue existante.

**Contenu intégralement en anglais**, commentaires HTML compris. Les commentaires
sont invisibles dans l'issue rendue mais parfaitement lisibles dans le fichier
source, que n'importe qui peut ouvrir sur un dépôt public.

Ces fichiers sont versionnés : ils s'ajoutent par le flux normal, une issue puis
une branche puis une pull request. Seule exception admise, la toute première issue
est créée sans template puisqu'ils n'existent pas encore, et son label est posé à
la main.

### Le front matter

Le bloc entre triples tirets est interprété par GitHub : `title` pré-remplit le
titre, `labels` applique le label automatiquement, `name` et `about` sont ce qui
s'affiche dans le sélecteur.

Adapter le préfixe de `title` à chaque dépôt : `[UI]`, `[API]`, `[DEPLOY]`.
L'espace final après le crochet fermant est volontaire.

Un template déclarant `labels: refactor` n'applique rien si le label n'existe pas
dans le dépôt. D'où l'ordre labels avant templates.

### Les cinq templates d'issue ne sont pas cinq copies

Chacun structure une nature de travail différente.

**`feature.md`** : Summary, Acceptance criteria, Technical notes, Branch,
Definition of done.

**`bug.md`** remplace `Acceptance criteria` par Steps to reproduce, Expected
behaviour, Actual behaviour. Un bug ne se décrit pas par des critères
d'acceptation mais par un écart. Sans étapes de reproduction, une issue de bug
rouverte trois semaines plus tard est inexploitable.

**`refactor.md`** ajoute une section `Behaviour preservation` et une `Definition of
done` disant « Unchanged behaviour verified in production ». C'est la définition
même d'un refactoring : si le comportement change, ce n'en est plus un. Forcer à
écrire comment on s'en assure est le seul garde-fou.

**`chore.md`** : proche de `feature.md`, notes techniques orientées versions et
ruptures de compatibilité.

**`docs.md`** allège la `Definition of done`, « vérifié en production » n'ayant pas
de sens pour de la documentation.

### Le template de pull request diffère par dépôt

C'est le seul fichier qui ne s'aligne pas entre dépôts, parce qu'il décrit un
pipeline, et que les pipelines diffèrent. Les templates d'issue, eux, décrivent une
méthode de travail et restent identiques.

La section `Tests` doit lister les contrôles réels du pipeline, dans leur ordre
d'exécution, et **marquer explicitement ceux qui sont en `continue-on-error`**.
Un contrôle non bloquant ne fera jamais échouer le CI : un CI vert ne dit rien de
son contenu, et sans mention explicite personne n'ouvrira jamais son rapport. La
case demande de l'avoir regardé, pas qu'il soit parfait.

Sur un dépôt sans pipeline, remplacer la section `Tests` par une section
`Manual checks` à lignes libres. Un template demandant de cocher des contrôles
inexistants finit par n'être plus lu du tout.

### Les cases à cocher

Syntaxe : `- [ ]` pour une case vide, `- [x]` pour une case cochée.
**L'espace entre les crochets est obligatoire.** Sans lui, GitHub affiche du texte
littéral avec des crochets au lieu de cases cliquables. Vérifier par l'onglet
`Preview` avant de valider.

Fonctionnement : on écrit `- [ ]` **une seule fois**, dans le template. Au moment de
créer l'issue ou la pull request, on les laisse vides. Une fois l'objet créé, le
Markdown est rendu et les cases deviennent **cliquables**. On les coche à la souris
au fur et à mesure. GitHub affiche un compteur et enregistre chaque clic dans la
timeline.

Cocher les cases restantes avant de clore, même quand ce n'est plus fonctionnel :
une issue archivée avec des cases vides suggère un travail inachevé à qui la relit.
Sur une issue de rattrapage, décrivant un travail terminé depuis des mois, les
cases sont écrites directement cochées.

### Créer une série d'issues en ligne de commande

Pour un rattrapage ou toute série d'issues rédigées d'avance, l'interface est
inutilement coûteuse. Rédiger un fichier `.md` par issue, dans un dossier hors
des clones, puis :

```powershell
gh issue create --repo <owner>/<repo> --title "[UI] <titre>" --label feat --label security --milestone "v1.0.0" --assignee "@me" --body-file .\1.1.md
```

`--body-file` lit le corps depuis le fichier, ce qui contourne définitivement le
problème PowerShell 5.1 des guillemets et des retours à la ligne dans un
argument. `--label` se répète pour chaque label. `"ci/cd"` doit être entre
guillemets à cause de la barre oblique. Aucune option `--project` n'est
nécessaire si l'auto-add pointe déjà sur le dépôt.

**Aucune sous-commande `gh` ne crée un lien parent-enfant.** Le rattachement se
fait dans l'interface : page du parent, bloc `Sub-issues`, `Add existing issue`,
numéro de l'enfant. Créer les parents en premier, puis les enfants par groupe, et
rattacher immédiatement après chaque groupe : une passe finale sur vingt lignes
est bien plus pénible que trois passes de trois. Les compteurs `n / n` du parent
confirment l'opération.

---

## 16. Limites de plan et impossibilités

### Workflows auto-add

| Plan | Maximum |
|------|---------|
| GitHub Free | **1** |
| GitHub Pro | 5 |
| GitHub Team | 5 |
| GitHub Enterprise Cloud | 20 |

En Free, un seul dépôt couvert à la fois. Le bouton `Duplicate workflow` est grisé
avec le message « Maximum number of auto-add workflows reached ». Voir la stratégie
de bascule en section 5.

L'ajout manuel n'est jamais limité. Trois méthodes : coller l'URL de l'issue dans la
dernière ligne du tableau du Project, taper `#` dans cette même ligne et chercher
l'issue, ou passer par la barre latérale droite de l'issue.

### Rulesets

Sur plan Free, les rulesets et la protection de branche ne sont disponibles que
pour les **dépôts publics**.

### Issue types

Les **issue types**, qui normalisent la classification entre dépôts, ne sont
disponibles que sur les Projects d'organisation. Sur un compte utilisateur, les
labels remplissent ce rôle.

### Hiérarchie dans la Roadmap

L'affichage hiérarchique n'est pas disponible dans la vue Roadmap. Limitation
connue, remontée par la communauté, sans date de correction annoncée. La parade est
la séparation `Roadmap overview` et `Roadmap detail`.

### Colonnes d'un Board groupé par itération

Un Board n'expose que l'itération courante et les trois qui la précèdent. Limite
non documentée, sans contournement connu. La parade est de construire la vue en
Table, où le regroupement n'a pas de fenêtre.

### Auto-approbation

**Impossible sur GitHub, quel que soit le plan.** Le formulaire de revue d'une
pull request dont on est l'auteur ne propose que `Comment`. Conséquences : le
workflow `Code review approved` ne se déclenche jamais en solo, et `Required
approvals` doit rester à zéro dans le ruleset.

### Ce que les API n'exposent pas

- Les **workflows intégrés** du Project : ni API REST, ni GraphQL, ni `gh`.
  Relevé manuel obligatoire.
- Les **couleurs et descriptions** des options d'un champ single select :
  `gh project field-list` ne les renvoie pas.
- Les **détails d'un champ Iteration** : `field-list` ne donne que l'identifiant,
  le nom et le type. Passer par GraphQL (voir section 10).
- Les **breaks** d'un champ Iteration : invisibles même en GraphQL.
- Les **vues** et leur configuration.
- La **création d'un lien parent-enfant** entre issues : aucune sous-commande
  `gh` ne le fait. Le rattachement passe obligatoirement par l'interface.
- Le réglage **`Auto-close issues with merged linked pull requests`** et le
  réglage **`Allow auto-merge`** : absents de la sortie de `gh api repos/...`.

---

## 17. Ce qui a été écarté et pourquoi

Cette section existe pour ne pas refaire deux fois la même analyse.

### Le flux « pull request d'abord »

**Écarté.** L'idée initiale était de générer une issue à partir de chaque pull
request après coup. Le problème est que l'issue devient un reçu et non un plan :
rien ne se trouve jamais en Backlog ni en In Progress, le kanban n'affiche que des
choses terminées, et un collaborateur ne sait ni ce qu'il peut prendre ni sur quoi
on travaille.

Retenu à la place : issue d'abord, puis branche, puis pull request.

### L'automatisation des dates par PAT

**Écartée.** Le `GITHUB_TOKEN` de GitHub Actions ne peut pas accéder aux Projects.
Il faut un personal access token ou une GitHub App, donc un secret longue durée dans
le pipeline.

Le vrai blocage n'est pas le risque de sécurité, il est fonctionnel : le déclencheur
souhaité serait « l'utilisateur a déplacé une carte vers In Progress », or les
changements de champ d'un Project ne génèrent pas d'événement de workflow exploitable
dans un dépôt. Le seul déclencheur réaliste est l'ouverture de la pull request, ce qui
placerait la date de début à la **fin** du travail. La donnée serait fausse.

Retenu à la place : saisie manuelle de `Start Date` et `End Date`, deux clics par
issue, rappelée par les descriptions des options de statut.

Si l'automatisation devient nécessaire un jour : fine-grained PAT limité à
`projects: read & write`, `issues: read-only`, `pull requests: read-only`, avec
expiration à six mois, dans un fichier de workflow **séparé** de celui du
déploiement, et documentation SECURITY mise à jour en conséquence.

### Abandonner le bouton Create a branch

**Écarté.** L'alternative consistait à créer les branches en local par
`git checkout -b`, pour que `Refs #N` retrouve son sens et que l'issue reste ouverte
jusqu'à la vérification, préservant l'alignement entre état et statut.

Écarté parce que le bouton fait avancer la carte automatiquement au merge, ce qui
retire un geste par cycle, et parce que l'association formelle branche-issue affiche
la branche dans la section Development. Le prix est le désalignement pendant
`Verifying`, assumé et documenté en section 3.

### Un second compte pour approuver ses pull requests

**Écarté.** Techniquement possible, mais c'est du théâtre : deux comptes
appartenant manifestement à la même personne s'approuvant mutuellement abîment
précisément ce qu'un portfolio cherche à démontrer.

### La branche develop et l'environnement de staging

**Écarté pour l'instant.** Une branche `develop` n'a de valeur que si elle est
déployée quelque part. Sans environnement de préproduction, elle ajoute une étape
administrative sans rien permettre de tester.

Le flux actuel s'appelle **GitHub Flow** : branche de feature, pull request, merge sur
`main`, déploiement. C'est un modèle légitime, courant en déploiement continu.

Le statut `Verifying` existe précisément pour compenser cette absence
d'environnement de préproduction.

### Les milestones comme phases

**Écarté.** Un milestone appartient à un **dépôt**, pas à un Project. Sur un projet
multi-dépôts, il faudrait dupliquer chaque phase à l'identique dans chaque dépôt,
sans lien entre eux et sans vue consolidée.

Retenu à la place : le champ `Phase` au niveau du Project, et les milestones
réaffectés aux versions.

### Un statut « Test »

**Écarté.** Écrire des tests n'est pas une étape du cycle de vie de toutes les issues,
c'est une issue à part entière portant le label `test`. Un statut doit être traversé
par toutes les issues sans exception.

### Un label perf

**Écarté.** Une seule occurrence dans tout le portfolio. Le commit concerné est
rangé sous une issue portant le label `refactor`.

### La vue By phase en Board

**Écartée en session 4.** C'était la construction naturelle, un `Column by: Phase`
sur un Board, et c'est celle qui avait été retenue en session 2. Un Board n'expose
qu'une fenêtre glissante de quatre itérations autour de la courante, ce qui rendait
quatre phases sur huit invisibles sans qu'aucun réglage ne le corrige.

Retenu à la place : une Table avec `Group by: Phase` et `Show hierarchy` désactivé.

### Le bloc Related PRs en ligne

**Écarté en session 4.** La première rédaction proposait `Related PRs: #1, #2` sur
une seule ligne dans le corps. Elle se noie dans le texte et n'apparaît pas dans le
sommaire automatique de l'issue.

Retenu à la place : une section `## Related PRs` de niveau 2, une ligne par pull
request, plus un rappel `(PR #N)` en fin de la ligne de commit correspondante.

### Les releases GitHub

**Reportées.** Un tag n'est pas une release. Publier trois releases `v1.0.0` avec
des notes générées depuis les issues de leur milestone rendrait les pages d'accueil
des dépôts nettement plus parlantes. À traiter une fois les tags stabilisés.

---

## Références

- Documentation GitHub Projects : `https://docs.github.com/en/issues/planning-and-tracking-with-projects`
- Automatisations intégrées : `https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-built-in-automations`
- Ajout automatique d'items : `https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/adding-items-automatically`
- Champs Iteration : `https://docs.github.com/en/issues/planning-and-tracking-with-projects/understanding-fields/about-iteration-fields`
- Personnalisation du Board : `https://docs.github.com/en/issues/planning-and-tracking-with-projects/customizing-views-in-your-project/customizing-the-board-layout`
- Fermeture automatique des issues : `https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/managing-auto-closing-issues`
- Conventional Commits : `https://www.conventionalcommits.org`
- Semantic Versioning : `https://semver.org`
