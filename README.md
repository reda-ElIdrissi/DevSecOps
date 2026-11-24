# EazyBank sécurisée

**JDK 21 LTS obligatoire pour Maven, Keycloak et IntelliJ.** Versions utilisées localement : Microsoft OpenJDK 21.0.13.1, Maven Wrapper 3.9.13, Spring Boot 4.1.3 et Keycloak 26.8.2.

Accounts agrège le compte, le prêt et la carte d'un client fictif. Keycloak émet les jetons de service. Chaque API vérifie le JWT et applique ses propres permissions. Les quatre processus s'exécutent en HTTPS sur la boucle locale.

## Démarrer sous Windows

Installer un JDK 21, OpenSSL, un `curl.exe` compilé avec OpenSSL et [Keycloak 26.8.2](https://github.com/keycloak/keycloak/releases/tag/26.8.2). Le ZIP officiel Keycloak a pour SHA-1 `987faddc433a9bf72f219e3654bd02b7685621bc`. Le téléchargement a été vérifié avec cette somme. Ajouter OpenSSL et curl au PATH, ou renseigner `EAZYBANK_CURL` avec le chemin du curl. Le curl Schannel intégré à Windows exige une information de révocation absente de la PKI de démonstration.

Depuis la racine, adapter les deux premiers chemins, puis exécuter dans PowerShell :

```powershell
$env:JAVA_HOME = 'C:\chemin\jdk-21'
$env:KEYCLOAK_HOME = 'C:\chemin\keycloak-26.8.2'
.\mvnw.cmd clean verify
.\scripts\start-local.ps1
.\scripts\test-e2e.ps1
.\scripts\stop-local.ps1
```

Le démarrage vérifie les ports 8080, 8090, 9000, 8443 et 9001 et génère la PKI au premier lancement. Les certificats, secrets, fichiers PID et logs restent dans `runtime/`. Le test de bout en bout dure quelques minutes, dont environ 2 min 30 pour observer l'expiration d'un vrai jeton. Il redémarre les processus nécessaires pendant la vérification et restaure la configuration. Lancer la suite sur une pile fraîche.

## Importer dans IntelliJ

Ouvrir le `pom.xml` racine en tant que projet. Choisir le SDK 21 pour le projet et Maven, puis sélectionner le Maven Wrapper. Les classes principales sont `AccountsApplication`, `LoansApplication` et `CardsApplication`. Pour la démonstration, lancer la pile depuis le terminal IntelliJ avec les commandes ci-dessus. Pour déboguer un seul service, arrêter ce processus avec `stop-local.ps1 <service>` et lancer sa classe principale dans IntelliJ avec les variables de `.env.example`. Utiliser les keystores propres au service et le truststore dans `runtime/pki/`, avec le mot de passe dans `runtime/pki/password`. Les deux secrets sortants d'Accounts se trouvent dans `runtime/secrets.json`.

## Permissions de démonstration

| API | Route | Client | Rôle |
| --- | --- | --- | --- |
| Accounts | GET /api/fetchCustomerDetails | `bank-client` | `SUMMARY_READ` |
| Loans | GET /api/fetch | `accounts-to-loans` | `LOANS_READ` |
| Cards | GET /api/fetch | `accounts-to-cards` | `CARDS_READ` |
| Cards | POST /api/create | `cards-operator` | `CARDS_WRITE` |

Pour consulter le dossier fictif sans afficher de jeton :

```powershell
. .\scripts\common.ps1
. .\scripts\e2e-requests.ps1
(Invoke-LocalRequest 'https://localhost:8080/api/fetchCustomerDetails?mobileNumber=0600000001' -Token (Get-TestToken bank-client)).Body
```

La référence métier B1/B2 est au commit `d46a25e`. Elle utilise HTTP sur loopback avec des données fictives et se reproduit dans un worktree séparé. La pile courante démarre en HTTPS avec des bases H2 réinitialisées à chaque redémarrage.
