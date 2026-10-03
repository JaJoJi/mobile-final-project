#!/usr/bin/env bash
# Gate proof (#287): "a gate that has never been seen red is not done".
# For each CI gate this makes a THROWAWAY branch from origin/dev that breaks
# exactly that gate with one small file, pushes it and opens a DRAFT PR into
# dev (the PR build runs every gate). Read the red build number from the PR,
# record it in docs/14-gate-evidence.md, then run `cleanup`.
#
#   bash ci/scripts/gate-proof.sh list
#   bash ci/scripts/gate-proof.sh create <gate|all>
#   bash ci/scripts/gate-proof.sh status         # PR -> Jenkins build links + state
#   bash ci/scripts/gate-proof.sh cleanup        # close the PRs, delete the branches
#
# Run a COPY of this script from outside the repo (it switches branches):
#   cp ci/scripts/gate-proof.sh /tmp/gp.sh && REPO_DIR=$PWD bash /tmp/gp.sh create all
# Needs: git, gh (authenticated). Never merge these PRs. The fake values are
# invented strings; nothing here is a real credential.
set -euo pipefail
cd "${REPO_DIR:-$(dirname "$(readlink -f "$0")")/../..}"

GATES=(typecheck unit-test game-coverage flutter-analyze flutter-format gitleaks semgrep trivy-fs checkov)
PREFIX=gate-proof

why() {
  case "$1" in
    typecheck)       echo "Backend · lint (tsc --noEmit): a type error" ;;
    unit-test)       echo "Backend · unit test: a failing assertion" ;;
    game-coverage)   echo "Backend · coverage floor: an untested file under src/game/ (< 90 %)" ;;
    flutter-analyze) echo "Mobile · flutter analyze: a type error" ;;
    flutter-format)  echo "Mobile · dart format --set-exit-if-changed: badly formatted file" ;;
    gitleaks)        echo "Security · Gitleaks: a fake API key matching generic-api-key" ;;
    semgrep)         echo "Security · Semgrep: eval() on request input" ;;
    trivy-fs)        echo "Security · Trivy fs: a requirements.txt pinning a vulnerable Django (fixed HIGH/CRITICAL)" ;;
    checkov)         echo "Security · Checkov: a Dockerfile with :latest, no USER, no HEALTHCHECK" ;;
  esac
}

break_gate() {
  case "$1" in
    typecheck)
      printf '%s\n' "// gate-proof: deliberate type error (never merge)" "export const gateProofTypecheck: number = 'not a number';" > backend/src/gate-proof-typecheck.ts ;;
    unit-test)
      printf '%s\n' "// gate-proof: deliberately failing test (never merge)" \
        "describe('gate-proof', () => { it('fails on purpose', () => { expect(1 + 1).toBe(3); }); });" > backend/src/gate-proof.spec.ts ;;
    game-coverage)
      { echo "// gate-proof: untested code in src/game/ pulls its coverage under 90 % (never merge)"
        echo "export function gateProofUncovered(n: number): number {"
        echo "  let t = 0;"
        for i in $(seq 1 60); do echo "  if (n === $i) { t += $i; } else { t -= $i; }"; done
        echo "  return t;"
        echo "}"; } > backend/src/game/gate-proof-uncovered.ts ;;
    flutter-analyze)
      printf '%s\n' "// gate-proof: deliberate analyzer error (never merge)" "const int gateProofAnalyze = 'not an int';" > mobile/lib/gate_proof_analyze.dart ;;
    flutter-format)
      printf '%s\n' "// gate-proof: deliberately unformatted (never merge)" "const   int   gateProofFormat=1 ;" "void   gateProofFn( ){  }" > mobile/lib/gate_proof_format.dart ;;
    gitleaks)
      printf '%s\n' "# gate-proof: fake key for gitleaks, not a credential (never merge)" \
        'api_key = "k3Gh29sLpQ7vXz81MnB4cD5eF6gH7iJ0uV2wX3yZ"' > gate-proof-secret.txt ;;
    semgrep)
      printf '%s\n' "// gate-proof: eval on request input (never merge)" \
        "export function gateProofEval(req: { query: { x: string } }) { return eval(req.query.x); }" > backend/src/gate-proof-semgrep.ts ;;
    trivy-fs)
      printf '%s\n' "# gate-proof: vulnerable pin (never merge)" "django==2.2.0" > gate-proof-requirements.txt ;;
    checkov)
      mkdir -p ci/gate-proof
      printf '%s\n' "# gate-proof: insecure Dockerfile (never merge)" "FROM node:latest" "ADD . /app" "CMD [\"node\", \"/app/x.js\"]" > ci/gate-proof/Dockerfile ;;
    *) echo "unknown gate: $1" >&2; return 1 ;;
  esac
}

create() {
  local g="$1" b="$PREFIX/$1"
  git fetch -q origin dev
  git checkout -q -B "$b" origin/dev
  break_gate "$g"
  git add -A
  git -c core.hooksPath=/dev/null commit -q -m "gate-proof($g): break one gate on purpose - DO NOT MERGE

$(why "$g")"
  git push -q -f origin "$b"
  gh pr create --draft -B dev -H "$b" -t "gate-proof: $g (red on purpose, do not merge)" \
    -b "Throwaway PR for #287. $(why "$g"). Expected: the matching Jenkins stage goes red. Closed + branch deleted after the evidence is recorded." >/dev/null
  echo "created $b"
  git checkout -q -
}

case "${1:-list}" in
  list)    for g in "${GATES[@]}"; do printf '%-16s %s\n' "$g" "$(why "$g")"; done ;;
  create)  target="${2:?gate name or all}"
           start="$(git rev-parse --abbrev-ref HEAD)"
           if [[ $target == all ]]; then for g in "${GATES[@]}"; do create "$g"; done; else create "$target"; fi
           git checkout -q "$start" ;;
  status)  gh pr list --state all --search "gate-proof in:title" --json number,title,state,headRefName,statusCheckRollup \
             -q '.[] | "#\(.number) \(.state) \(.headRefName)  " + ([.statusCheckRollup[]? | select(.context != null) | "\(.state) \(.targetUrl)"] | join(" | "))' ;;
  cleanup) for n in $(gh pr list --state open --search "gate-proof in:title" --json number -q '.[].number'); do
             gh pr close "$n" --delete-branch --comment "Evidence recorded in docs/14-gate-evidence.md; closing the throwaway PR." >/dev/null && echo "closed #$n"
           done
           for g in "${GATES[@]}"; do git push -q origin --delete "$PREFIX/$g" 2>/dev/null || true; done ;;
  *) sed -n 2,16p "$0"; exit 1 ;;
esac
