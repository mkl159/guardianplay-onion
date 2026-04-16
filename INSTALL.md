# ⚙️ GuardianPlay — Guide d'installation complet

## 📋 Prérequis

| Élément | Version requise |
|---------|----------------|
| Console | Miyoo Mini **ou** Miyoo Mini+ |
| OS | **Onion OS 4.3.0** ou supérieur |
| Carte SD | Accessible depuis un PC |

---

## 🚀 Installation rapide (5 minutes)

### Étape 1 — Préparer la carte SD

Insérez la carte SD de votre Miyoo Mini dans votre PC.

### Étape 2 — Copier les fichiers de l'application

Copiez le dossier `src/App/ParentalControl/` vers la racine de votre SD :

```
[Lettre SD]:\App\ParentalControl\
```

**Structure attendue sur la SD :**
```
SD:\
├── App\
│   └── ParentalControl\
│       ├── config.json
│       ├── launch.sh
│       ├── parental_ui.sh
│       ├── parental_daemon.sh
│       ├── parental_hook.sh
│       ├── install.sh
│       ├── uninstall.sh
│       ├── lang\
│       │   ├── en.sh
│       │   ├── fr.sh
│       │   └── es.sh
│       └── res\
│           └── guardianplay.png
```

### Étape 3 — Copier l'icône

Copiez l'icône de l'application :

**Source :** `src/App/ParentalControl/res/guardianplay.png`  
**Destination :** `SD:\Icons\Default\app\guardianplay.png`

```
SD:\
└── Icons\
    └── Default\
        └── app\
            └── guardianplay.png   ✅
```

> 💡 Si le dossier `Icons\Default\app\` n'existe pas, créez-le.

### Étape 4 — Éjecter et insérer la SD

Éjectez proprement la carte SD depuis votre PC et réinsérez-la dans la console.

### Étape 5 — Lancer l'installeur sur la console

**Option A — Via l'app Terminal d'Onion OS :**

1. Allumez votre Miyoo Mini
2. Ouvrez le menu **Apps**
3. Lancez **Terminal**
4. Tapez la commande :
```sh
sh /mnt/SDCARD/App/ParentalControl/install.sh
```

**Option B — Via SSH (si Wi-Fi configuré) :**
```sh
ssh root@<adresse_ip_console>
sh /mnt/SDCARD/App/ParentalControl/install.sh
```

**Option C — Via FTP/SFTP :**
Connectez-vous en FTP et exécutez le script depuis votre client FTP.

### Étape 6 — Redémarrer

Éteignez et rallumez votre Miyoo Mini.

### Étape 7 — Premier lancement

1. Allez dans le menu **Apps**
2. Cliquez sur **GuardianPlay** 🛡️
3. Créez votre code PIN à 4 chiffres
4. Configurez le temps de jeu

---

## 🔧 Ce que fait l'installeur

Le script `install.sh` effectue les opérations suivantes :

### ✅ Backup de sécurité
```
/mnt/SDCARD/.tmp_update/runtime.sh
    → sauvegardé vers runtime.sh.gp_backup
```

### ✅ Injection du hook dans runtime.sh

Le script injecte 12 lignes dans `runtime.sh` après l'appel `playActivity start` :

```sh
# === GUARDIANPLAY HOOK ===
# Block game launch if parental time is exhausted
if [ -f "/mnt/SDCARD/App/ParentalControl/parental_hook.sh" ]; then
    /mnt/SDCARD/App/ParentalControl/parental_hook.sh "$rompath"
    if [ $? -ne 0 ]; then
        playActivity stop "$rompath" 2>/dev/null
        rm -f $sysdir/cmd_to_run.sh 2>/dev/null
        return
    fi
fi
# === END GUARDIANPLAY HOOK ===
```

### ✅ Installation du script de démarrage du démon

Crée le fichier :
```
/mnt/SDCARD/.tmp_update/startup/guardianplay.sh
```

Ce fichier est automatiquement exécuté par Onion OS à chaque démarrage.

### ✅ Création de la configuration par défaut
```
/mnt/SDCARD/App/ParentalControl/data/config.cfg
```

---

## 🗑️ Désinstallation

```sh
sh /mnt/SDCARD/App/ParentalControl/uninstall.sh
```

Le script de désinstallation :
- Arrête le démon GuardianPlay
- Supprime le script de démarrage
- **Restaure le `runtime.sh` original** depuis le backup (ou supprime les lignes injectées)
- **Préserve vos données** (stats, historique, config)

> ⚠️ Après désinstallation, redémarrez la console.

---

## 🔄 Mise à jour

Pour mettre à jour GuardianPlay :

1. Désinstallez l'ancienne version :
```sh
sh /mnt/SDCARD/App/ParentalControl/uninstall.sh
```

2. Remplacez les fichiers sur la SD

3. Réinstallez :
```sh
sh /mnt/SDCARD/App/ParentalControl/install.sh
```

> 💾 Vos données (config, PIN, stats, historique) dans le dossier `data/` sont **préservées**.

---

## 🆘 Restauration d'urgence

Si votre Miyoo Mini ne démarre plus après l'installation :

1. Insérez la SD dans votre PC
2. Naviguez vers `SD:\.tmp_update\`
3. Copiez `runtime.sh.gp_backup` et renommez-le `runtime.sh`
4. Réinsérez la SD et rallumez

---

## 📞 Support

- **GitHub Issues :** [github.com/mkl159/guardianplay-onion/issues](https://github.com/mkl159/guardianplay-onion/issues)
- **Forum Onion OS :** [discord.gg/onionos](https://discord.gg/onionos)
