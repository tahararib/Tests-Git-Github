#!/usr/bin/env bash
#
# bootstrap-formation-git.sh
# -----------------------------------------------------------------------------
# Reconstruit le depot fil rouge "webapp-deployment" de la formation Git,
# avec son historique complet, jusqu'a l'etape demandee.
#
#   Usage :  bash bootstrap-formation-git.sh [etape]
#
#   etape 1 : fin du chapitre 1 (Le premier cycle)
#   etape 2 : fin du chapitre 2 (Sous le capot)
#   etape 3 : fin du chapitre 3 (Cycle de vie des fichiers)
#   etape 4 : fin du chapitre 4 (Defaire)
#   etape 5 : fin du chapitre 5 (Branches et fusion)       <- pour refaire la demo C6
#   etape 6 : fin de la demo du chapitre 6 (Rebase)        <- DEFAUT
#   etape 7 : fin du chapitre 7 (Depot central --bare + clone collegue)
#
# Les commits historiques ont des auteurs et des dates figes : les empreintes
# SHA sont donc IDENTIQUES sur toutes les machines. Les commits que vous ferez
# ensuite porteront votre propre identite.
# -----------------------------------------------------------------------------

set -euo pipefail

ETAPE="${1:-6}"
REPO="${HOME}/webapp-deployment"
SRV="${HOME}/srv/webapp-deployment.git"
CLONE="${HOME}/collegue"

A1_N="Jean Dupont";  A1_E="jean.dupont@exemple.fr"
A2_N="Marc Leroy";   A2_E="marc.leroy@exemple.fr"

N=0
BASE_EPOCH=1770624000          # 2026-02-09 09:00:00 UTC, deterministe

# -----------------------------------------------------------------------------
# Utilitaires
# -----------------------------------------------------------------------------
say()  { printf '\033[1;36m==\033[0m %s\n' "$*"; }
ok()   { printf '   \033[0;32mOK\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

# Commit avec auteur et date figes.  cmt <n_auteur> <message>
cmt() {
  local who="$1"; shift
  local name mail stamp
  if [ "$who" = "2" ]; then name="$A2_N"; mail="$A2_E"; else name="$A1_N"; mail="$A1_E"; fi
  N=$((N+1))
  stamp="$(date -u -d "@$((BASE_EPOCH + N*1020))" +"%Y-%m-%dT%H:%M:%S" 2>/dev/null \
        || date -u -r "$((BASE_EPOCH + N*1020))" +"%Y-%m-%dT%H:%M:%S")"
  GIT_AUTHOR_NAME="$name"     GIT_AUTHOR_EMAIL="$mail"     GIT_AUTHOR_DATE="${stamp}+0000" \
  GIT_COMMITTER_NAME="$name"  GIT_COMMITTER_EMAIL="$mail"  GIT_COMMITTER_DATE="${stamp}+0000" \
  git commit -q "$@"
}

# -----------------------------------------------------------------------------
# 0. Verifications et configuration globale
# -----------------------------------------------------------------------------
say "Verification de l'environnement"
command -v git >/dev/null || die "git introuvable dans le PATH."
ok "$(git --version)"

case "$ETAPE" in 1|2|3|4|5|6|7) ;; *) die "Etape inconnue : $ETAPE (attendu 1 a 7)." ;; esac

if [ -e "$REPO" ]; then
  SAUVE="${REPO}.sauvegarde-$(date +%Y%m%d-%H%M%S)"
  mv "$REPO" "$SAUVE"
  warn "Un depot existait deja : deplace vers $SAUVE"
fi
rm -rf "$CLONE" "${HOME}/srv"

say "Configuration globale de Git (chapitre 0)"
git config --global init.defaultBranch main
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) git config --global core.autocrlf true ;;
  *)                    git config --global core.autocrlf input ;;
esac
git config --global core.safecrlf false
git config --global alias.lg "log --graph --decorate --oneline --all"
git config --global alias.st "status -sb"
git config --global merge.conflictStyle zdiff3
git config --global pull.rebase true
git config --global fetch.prune true
git config --global core.pager cat
git config --global --get core.editor >/dev/null 2>&1 || git config --global core.editor "notepad"
ok "init.defaultBranch, core.autocrlf, alias lg et st, merge.conflictStyle..."

if ! git config --global --get user.name >/dev/null 2>&1; then
  git config --global user.name  "${GIT_NAME:-Participant Formation}"
  git config --global user.email "${GIT_EMAIL:-participant@exemple.fr}"
  warn "IDENTITE PROVISOIRE POSEE. Remplacez-la maintenant par la votre :"
  printf '     git config --global user.name  "Prenom Nom"\n'
  printf '     git config --global user.email "prenom.nom@exemple.fr"\n'
else
  ok "Identite : $(git config --global --get user.name) <$(git config --global --get user.email)>"
fi

# -----------------------------------------------------------------------------
# Finalisation
# -----------------------------------------------------------------------------
finaliser() {
  git config --local --unset core.autocrlf 2>/dev/null || true
  git reset -q --hard
  local n; n=$(git status --porcelain | wc -l)
  if [ "$n" -ne 0 ]; then warn "$n fichier(s) non aligne(s) apres finalisation"; fi
}

# -----------------------------------------------------------------------------
# CHAPITRE 1 — Le premier cycle
# -----------------------------------------------------------------------------
say "Chapitre 1 — Le premier cycle"
mkdir -p "$REPO" && cd "$REPO"
git init -q
# Neutralise la conversion de fins de ligne PENDANT la construction, pour que
# les outils texte (sed, grep) travaillent sur du LF. Retire a la fin.
git config --local core.autocrlf false
mkdir -p app k8s ansible scripts docs

cat > scripts/validate.sh <<'VEOF'
#!/usr/bin/env bash
# validate.sh - controle des artefacts versionnes du depot.
set -u
err=0

echo "== 1. Syntaxe des scripts shell =="
for f in $(git ls-files '*.sh'); do
  if bash -n "$f" 2>/dev/null; then echo "   OK    $f"
  else echo "   ECHEC $f"; err=$((err+1)); fi
done

echo "== 2. Marqueurs de conflit non resolus =="
if git grep -lE '^(<<<<<<< |>>>>>>> )' -- . >/dev/null 2>&1; then
  git grep -lE '^(<<<<<<< |>>>>>>> )' -- . | sed 's/^/   ECHEC /'
  err=$((err+1))
else echo "   OK    aucun marqueur"; fi

echo "== 3. Cles obligatoires des manifests =="
for f in $(git ls-files 'k8s/*.yaml'); do
  if grep -q '^kind:' "$f" && grep -q '^apiVersion:' "$f"; then echo "   OK    $f"
  else echo "   ECHEC $f (apiVersion ou kind manquant)"; err=$((err+1)); fi
done

echo "== 4. Image applicative =="
if [ -f app/Dockerfile ]; then
  if grep -q '^FROM ' app/Dockerfile && grep -qE '^(CMD|ENTRYPOINT) ' app/Dockerfile
  then echo "   OK    app/Dockerfile"
  else echo "   ECHEC app/Dockerfile (FROM ou CMD manquant)"; err=$((err+1)); fi
fi

if [ "$err" -eq 0 ]; then echo "VALIDATION OK"; exit 0
else echo "VALIDATION KO ($err probleme(s))"; exit 1; fi
VEOF
chmod +x scripts/validate.sh

printf '# webapp-deployment\n\nArtefacts de deploiement de la webapp.\n' > README.md
git add README.md scripts/validate.sh
cmt 1 -m "chore: initialise le depot et le script de validation"

cat > app/server.js <<'EOF'
const http = require('http');
const port = process.env.PORT || 8080;

http.createServer((req, res) => {
  if (req.url === '/healthz') { res.writeHead(200); return res.end('ok'); }
  res.writeHead(200, {'Content-Type': 'text/plain'});
  res.end('webapp v1\n');
}).listen(port);
EOF
cat > app/Dockerfile <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY server.js .
EXPOSE 8080
CMD ["node", "server.js"]
EOF
git add app/
cmt 1 -m "feat: ajoute le service web et son image"

cat > k8s/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: webapp
          image: webapp:1.0.0
EOF
cat > k8s/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: webapp
spec:
  ports:
    - port: 80
      targetPort: 8080
EOF
git add k8s/
cmt 1 -m "chore: ajoute les manifests de deploiement et de service"

cat > docs/runbook.md <<'EOF'
# Runbook

## Incident : pods en CrashLoopBackOff
1. Verifier les logs du conteneur.
2. Verifier que /healthz repond.
3. Revenir a la version precedente si necessaire.
EOF
git add docs/runbook.md
cmt 1 -m "docs: ajoute le runbook d exploitation"

printf '  minReadySeconds: 10\n' >> k8s/deployment.yaml
git add k8s/deployment.yaml
cmt 1 -m "chore: fiabilise le rollout (minReadySeconds a 10s)"
ok "5 commits"
[ "$ETAPE" -le 1 ] && { finaliser; bash scripts/validate.sh | tail -1; git lg; exit 0; }

# -----------------------------------------------------------------------------
# CHAPITRE 2 — Sous le capot  (aucun commit : lab en lecture seule)
# -----------------------------------------------------------------------------
say "Chapitre 2 — Sous le capot (lab d'observation, aucun commit)"
ok "etat inchange"
[ "$ETAPE" -le 2 ] && { finaliser; bash scripts/validate.sh | tail -1; git lg; exit 0; }

# -----------------------------------------------------------------------------
# CHAPITRE 3 — Cycle de vie des fichiers
# -----------------------------------------------------------------------------
say "Chapitre 3 — Cycle de vie des fichiers"
mkdir -p secrets logs
echo "DB_PASSWORD=Sup3rS3cret!" > secrets/prod.env
echo "2026-02-09 deploiement ok" > logs/deploy.log
git add .
cmt 1 -m "chore: ajoute la configuration de production"

git rm -r -q --cached secrets logs
cmt 1 -m "chore: retire la configuration de production du depot"

cat > .gitignore <<'EOF'
# Secrets et configuration d'environnement
secrets/
*.env
!example.env

# Artefacts et journaux
logs/
*.log
node_modules/

# Fichiers temporaires
tmp/
*.tmp
EOF
git add .gitignore
cmt 1 -m "chore: ajoute les regles d exclusion du depot"

echo "trace applicative" > app/debug.log
git add -f app/debug.log
cmt 1 -m "chore: ajoute une trace"

git rm -q --cached app/debug.log
cmt 1 -m "chore: cesse de suivre les traces applicatives"

printf 'DB_PASSWORD=changeme\nDB_HOST=localhost\n' > example.env
git add example.env
cmt 1 -m "docs: ajoute un modele de configuration d environnement"
ok "6 commits (dont l'incident du secret, toujours present dans l'historique)"
[ "$ETAPE" -le 3 ] && { finaliser; bash scripts/validate.sh | tail -1; git lg; exit 0; }

# -----------------------------------------------------------------------------
# CHAPITRE 4 — Defaire
# -----------------------------------------------------------------------------
say "Chapitre 4 — Defaire"
printf '  sessionAffinity: ClientIP\n' >> k8s/service.yaml
git add k8s/service.yaml
cmt 1 -m "chore: active l affinite de session sur le service"

printf '  externalTrafficPolicy: Local\n' >> k8s/service.yaml
git add k8s/service.yaml
cmt 1 -m "chore: restreint le routage du trafic externe au noeud local"

printf '\n## Deploiement\nVoir docs/runbook.md\n' >> README.md
git add README.md
cmt 1 -m "docs: renvoie vers le runbook depuis le README"

printf '# Document obsolete\n' > docs/obsolete.md
git add docs/obsolete.md
cmt 1 -m "docs: ajoute une note obsolete"
printf 'contenu supplementaire\n' >> docs/obsolete.md
git add docs/obsolete.md
cmt 1 -m "docs: complete la note obsolete"

# Les deux revert, du plus recent au plus ancien.
# Les empreintes sont resolues AVANT, car HEAD se decale au premier commit.
SHA_B="$(git rev-parse HEAD)"      # docs: complete la note obsolete
SHA_A="$(git rev-parse HEAD~1)"    # docs: ajoute la note obsolete
for r in "$SHA_B" "$SHA_A"; do
  MSG="Revert \"$(git log -1 --format=%s "$r")\""
  git revert --no-commit "$r" >/dev/null
  cmt 1 -m "$MSG"
done
ok "7 commits (dont 2 annulations par revert)"
[ "$ETAPE" -le 4 ] && { finaliser; bash scripts/validate.sh | tail -1; git lg; exit 0; }

# -----------------------------------------------------------------------------
# CHAPITRE 5 — Branches et fusion
# -----------------------------------------------------------------------------
say "Chapitre 5 — Branches et fusion"

# -- Demo : conflit scale-up (3 vs 5), resolu a 5
git switch -q -c feature/scale-up
sed -i 's/replicas: 2/replicas: 5/' k8s/deployment.yaml
git add k8s/deployment.yaml
cmt 1 -m "feat: passe la webapp a 5 replicas"
git switch -q main
sed -i 's/replicas: 2/replicas: 3/' k8s/deployment.yaml
git add k8s/deployment.yaml
cmt 1 -m "feat: passe la webapp a 3 replicas"
git merge -q --no-commit feature/scale-up >/dev/null 2>&1 || true
# Resolution : on retient la version de la branche fusionnee (5 replicas).
git checkout --theirs -- k8s/deployment.yaml
git add k8s/deployment.yaml
cmt 1 -m "Merge branch 'feature/scale-up'"
git branch -q -d feature/scale-up

# -- Lab M1 : fast-forward
git switch -q -c feature/healthcheck
cat >> k8s/deployment.yaml <<'EOF'
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
EOF
git add k8s/deployment.yaml
cmt 1 -m "feat: ajoute la sonde de vivacite sur la webapp"
git switch -q main
git merge -q --ff-only feature/healthcheck
git branch -q -d feature/healthcheck

# -- Lab M2 : fusion a trois points
git switch -q -c feature/rollback
cat > scripts/rollback.sh <<'EOF'
#!/usr/bin/env bash
set -eu
echo "Retour a la revision precedente du deploiement"
kubectl rollout undo deployment/webapp
EOF
chmod +x scripts/rollback.sh
git add scripts/rollback.sh
cmt 1 -m "feat: ajoute le script de retour arriere"
git switch -q main
printf '\n## Incident : deploiement echoue\nLancer scripts/rollback.sh\n' >> docs/runbook.md
git add docs/runbook.md
cmt 1 -m "docs: documente la procedure de retour arriere"
git merge -q --no-commit --no-ff feature/rollback
cmt 1 -m "Merge branch 'feature/rollback'"
git branch -q -d feature/rollback

# -- Lab M3-M5 : conflit tuning (4 vs 8), resolu a 6
git switch -q -c feature/tuning
sed -i 's/replicas: 5/replicas: 8/' k8s/deployment.yaml
git add k8s/deployment.yaml
cmt 1 -m "feat: monte la capacite a 8 replicas"
git switch -q main
sed -i 's/replicas: 5/replicas: 4/' k8s/deployment.yaml
git add k8s/deployment.yaml
cmt 1 -m "feat: ajuste la capacite a 4 replicas"
git merge -q --no-commit feature/tuning >/dev/null 2>&1 || true
# Resolution : ni 4 ni 8, une troisieme valeur decidee (6 replicas).
git checkout --ours -- k8s/deployment.yaml
sed -i 's/^\( *\)replicas: 4$/\1replicas: 6/' k8s/deployment.yaml
git add k8s/deployment.yaml
cmt 1 -m "Merge branch 'feature/tuning'"
git branch -q -d feature/tuning
ok "3 branches fusionnees, 2 conflits resolus, replicas a 6"
[ "$ETAPE" -le 5 ] && { finaliser; bash scripts/validate.sh | tail -1; git lg | head -14; exit 0; }

# -----------------------------------------------------------------------------
# CHAPITRE 6 — Rebase (etat d'apres la demonstration)
# -----------------------------------------------------------------------------
say "Chapitre 6 — Rebase (demonstration)"
printf '\n## Supervision\nAlertes sur le taux d erreur.\n' >> docs/runbook.md
git add docs/runbook.md
cmt 1 -m "docs: ajoute la section supervision"

# feature/metrics : resultat du rebase -i (3 commits brouillons -> 2 propres),
# puis rebase sur main. La branche n'est pas fusionnee : c'est l'etat reel.
git switch -q -c feature/metrics
cat >> k8s/deployment.yaml <<'EOF'
          ports:
            - containerPort: 9090
              name: metrics
EOF
git add k8s/deployment.yaml
cmt 1 -m "feat: expose les metriques applicatives sur le port 9090"
printf '\n## Metriques\nExposees sur le port 9090, chemin /metrics.\n' >> docs/runbook.md
git add docs/runbook.md
cmt 1 -m "docs: documente l exposition des metriques"
git switch -q main
ok "feature/metrics prete (2 commits), non fusionnee"
[ "$ETAPE" -le 6 ] && {
  finaliser
  bash scripts/validate.sh | tail -1
  echo
  git lg | head -18
  echo
  say "Depot reconstruit dans $REPO"
  printf '   Reprise : chapitre 6, Lab 7 (rebase interactif) puis Lab 8 (bisect).\n\n'
  printf '   \033[1;33mA COLLER DANS LE CHAT :\033[0m main = %s | %s commits\n' \
         "$(git rev-parse --short main)" "$(git rev-list --count main)"
  printf '   (tout le monde doit afficher la meme empreinte)\n'
  exit 0
}

# -----------------------------------------------------------------------------
# CHAPITRE 7 — Depot central et clone collegue
# -----------------------------------------------------------------------------
say "Chapitre 7 — Depot central --bare et clone collegue"
finaliser
git switch -q main
git merge -q --ff-only feature/metrics 2>/dev/null || git merge -q --no-ff --no-edit feature/metrics
git branch -q -D feature/metrics 2>/dev/null || true

mkdir -p "${HOME}/srv"
git init -q --bare "$SRV"
git remote add origin "$SRV"
git push -q -u origin main
git clone -q "$SRV" "$CLONE"
git -C "$CLONE" config --local user.name  "$A2_N"
git -C "$CLONE" config --local user.email "$A2_E"
ok "depot nu dans $SRV, clone dans $CLONE (identite : $A2_N)"
bash scripts/validate.sh | tail -1
echo
git lg | head -12
