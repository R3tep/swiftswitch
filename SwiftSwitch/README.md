# SwiftSwitch

Application macOS pour gerer plusieurs fenetres d'une meme application (ou de plusieurs). Elle permet de naviguer rapidement entre tes fenetres avec la touche Tab et de mettre le focus sur la fenetre qui doit etre active. Ideal pour les jeux multi-comptes (comme Dofus), les environnements multi-ecrans, ou tout workflow necessitant un switch rapide entre fenetres.

## Fonctionnalites

- **Gestion de fenetres** : selectionne jusqu'a 8 fenetres (de n'importe quelle application) a suivre
- **Switch rapide avec Tab** : appuie sur Tab quand tu es sur une fenetre suivie pour passer a la suivante
- **Ordre personnalisable** : reorganise l'ordre des fenetres par glisser-deposer dans la sidebar
- **Notifications** : affiche les notifications envoyees par les applications suivies dans un journal
- **Auto-focus** : quand une fenetre suivie envoie une notification, l'app bascule automatiquement dessus
- **Labels personnalises** : renomme chaque fenetre (ex: "Compte 1", "Navigateur", "Terminal"...)

## Prerequis

- **macOS 13 (Ventura)** ou plus recent
- **Xcode Command Line Tools** installe sur le Mac

### Installer les Command Line Tools

Ouvre le Terminal (Applications > Utilitaires > Terminal) et tape :

```bash
xcode-select --install
```

Une fenetre va s'ouvrir pour te proposer l'installation. Clique sur "Installer" et attends la fin.

## Installation

### 1. Telecharger le projet

Copie le dossier `SwiftSwitch` sur ton Mac, par exemple dans `~/Documents/app/SwiftSwitch`.

### 2. Compiler l'application

Ouvre le Terminal et tape :

```bash
cd ~/Documents/app/SwiftSwitch
swift build
```

La premiere compilation peut prendre environ 1 minute. Les suivantes seront quasi instantanees.

### 3. Lancer l'application

Toujours dans le Terminal :

```bash
swift run SwiftSwitch
```

L'application va s'ouvrir dans une fenetre.

## Permissions requises

Au premier lancement, macOS va te demander deux autorisations. **Les deux sont indispensables** pour que l'app fonctionne correctement.

### Accessibilite (obligatoire)

Cette permission permet a l'app de :

- Ecouter la touche Tab pour switcher entre les fenetres
- Mettre le focus sur la bonne fenetre

L'app affiche automatiquement la demande au lancement. Si tu l'as refusee par erreur :

1. Ouvre **Reglages Systeme** > **Confidentialite et securite** > **Accessibilite**
2. Clique sur le **+** et ajoute SwiftSwitch (ou le Terminal si tu lances via `swift run`)
3. Active le toggle a cote de l'app

### Enregistrement d'ecran (recommande)

Cette permission permet a l'app de lire les **noms** des fenetres (ex: "MonApp - Document1"). Sans elle, l'app fonctionne quand meme mais affiche uniquement le nom de l'application (ex: "MonApp") sans le detail.

1. Ouvre **Reglages Systeme** > **Confidentialite et securite** > **Enregistrement d'ecran**
2. Ajoute et active SwiftSwitch (ou le Terminal)

> Apres avoir accorde une permission, il faut parfois **relancer l'app** pour qu'elle prenne effet.

## Utilisation

### Ajouter des fenetres

1. Lance tes applications normalement
2. Dans SwiftSwitch, clique sur **"+ Ajouter"** en bas a gauche
3. Une fenetre s'ouvre avec toutes les fenetres detectees sur ton ecran
4. Utilise la barre de recherche pour filtrer (par exemple le nom de l'application)
5. Clique sur **"Ajouter"** a cote de chaque fenetre que tu veux suivre
6. Clique sur **"Fermer"**

### Renommer une fenetre

Double-clique sur le nom d'une fenetre dans la sidebar pour le modifier. Par exemple, renomme-la "Compte 1", "Navigateur", "Terminal", etc.

### Changer l'ordre des fenetres

Glisse-depose les fenetres dans la sidebar pour changer leur ordre. L'ordre definit la sequence quand tu appuies sur Tab :

```
Fenetre 1 -> Tab -> Fenetre 2 -> Tab -> Fenetre 3 -> Tab -> Fenetre 1 ...
```

### Retirer une fenetre

Fais un **clic droit** sur une fenetre dans la sidebar et choisis **"Retirer"**.

### Utiliser le switch Tab

1. Place tes fenetres les unes sur les autres (meme position, meme taille)
2. Quand tu es sur une fenetre suivie, appuie sur **Tab** pour passer a la suivante
3. Fais ton action (clic, frappe, etc.)
4. Appuie a nouveau sur **Tab** pour passer a la fenetre suivante

Exemple de workflow pour un jeu multi-comptes (comme Dofus) :

- **Tab** (passe au compte suivant)
- **Clic** (joue ton tour)
- **Tab** (passe au compte suivant)
- **Clic** (joue ton tour)
- ...

### Notifications et auto-focus

L'app surveille les notifications envoyees par les applications suivies. Quand une notification arrive, l'app peut basculer automatiquement sur la fenetre concernee.

Pour que cette fonctionnalite marche, les notifications de l'application suivie doivent etre activees dans Reglages Systeme > Notifications.

### Journal des notifications

En cliquant sur une fenetre dans la sidebar, tu peux voir le journal des notifications recues. Tu peux :

- **Filtrer** les notifications avec la barre de recherche
- **Effacer** le journal avec le bouton "Effacer"
- Activer/desactiver l'**auto-scroll** pour suivre les nouvelles notifications en temps reel

## Structure du projet

```
SwiftSwitch/
├── Package.swift                          # Configuration du projet Swift
└── Sources/SwiftSwitch/
    ├── SwiftSwitchApp.swift               # Point d'entree de l'application
    ├── Models/
    │   ├── TrackedWindow.swift            # Modele d'une fenetre suivie
    │   └── LogEntry.swift                 # Modele d'une notification
    ├── Services/
    │   ├── WindowManager.swift            # Detection et gestion des fenetres
    │   ├── WindowSwitchService.swift      # Ecoute de la touche Tab
    │   └── NotificationWatcherService.swift # Surveillance des notifications
    └── Views/
        ├── ContentView.swift              # Layout principal
        ├── SidebarView.swift              # Liste des fenetres suivies
        ├── LogView.swift                  # Journal des notifications
        └── WindowPickerView.swift         # Selection des fenetres a suivre
```

## Depannage

### L'app ne detecte pas mes fenetres

- Verifie que les fenetres sont bien **ouvertes et visibles** sur l'ecran
- Clique sur le bouton **rafraichir** (fleche circulaire) en bas de la sidebar
- Accorde la permission **Enregistrement d'ecran** pour voir les noms detailles

### Le Tab ne change pas de fenetre

- Verifie que la permission **Accessibilite** est accordee
- Verifie que tu as au moins **2 fenetres** dans la sidebar
- Relance l'app apres avoir accorde la permission

### L'app reste en arriere-plan

- C'est normal au tout premier lancement. Clique sur l'icone dans le Dock pour la ramener au premier plan
- Si le probleme persiste, relance l'app

### Les notifications ne s'affichent pas

- Verifie que les notifications de l'application sont **activees** dans Reglages Systeme > Notifications
- Les notifications n'apparaissent que quand l'application en envoie
