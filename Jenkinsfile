// Jenkins declarative pipeline for mobile-final-project.
//
// Flow (DevOps Master Guide A1/A5 — cheapest first, independent checks in
// parallel, artifact-dependent steps in sequence):
//
//   Secrets (Gitleaks)                                   every branch
//   PR checks  [parallel, failFast]
//     ├─ Backend  lint + build + unit test + coverage    PRs into dev/main, dev, main
//     ├─ Mobile   format + analyze + test + coverage     PRs into dev/main, dev, main
//     ├─ Semgrep  SAST                                   every branch
//     ├─ Trivy fs deps + secrets + IaC                   every branch
//     └─ Checkov  Dockerfiles + workflows                every branch
//   Backend image  build → SBOM → Trivy image scan       PRs into dev/main, dev, main
//   Ephemeral stack  PG + Redis + 3×Nest from that image
//     ├─ integration smoke (real infra)
//     └─ ZAP baseline + API scan
//   Publish to Docker Hub                                main only (dev → main merge)
//
// Every tool runs in a container pinned by version + digest, so the host
// only needs Jenkins + Docker, and a build is reproducible. Shell logic
// for the ephemeral stack lives in ci/scripts/ so it can be run and
// debugged outside Jenkins too.
//
// Host requirements + controller setup: docs/08-runbook.md §6.
// Credentials (Jenkins > Credentials), only needed by gated stages:
//   - dockerhub-token  Username + password/PAT  (ENABLE_IMAGE_PUBLISH)
//   - notify-email     Secret text: recipient(s), comma-separated
//                      (ENABLE_NOTIFICATIONS; kept out of this public repo)
//   Email also needs SMTP set in Manage Jenkins > System > Extended E-mail
//   Notification (runbook §6).

// Pinned tool images — bump deliberately (verify the new version first;
// Trivy's own releases were compromised in Mar 2026, guide A3).
IMAGES = [
  node    : 'node:22.23.3-bookworm-slim@sha256:43ac6c60b8f89723f746e8a92ce91abd5017e627ce1ddfe4238355d3a30b772c',
  flutter : 'ghcr.io/cirruslabs/flutter:3.44.0@sha256:46691e311715845de03a3ba4753a475476936805b29431b1f00f1816981033f8',
  gitleaks: 'zricethezav/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f',
  semgrep : 'semgrep/semgrep:1.178.0@sha256:32e459968daabe7ab86968184a29109b9564aa00392401156f9788452b42786b',
  trivy   : 'aquasec/trivy:0.74.0@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969',
  checkov : 'bridgecrew/checkov:3.3.19@sha256:d3e96adafdb315ca82e792ca8708c01adae85292800fb064c8b309b3d0cb7b80',
  zap     : 'zaproxy/zap-stable:2.17.0@sha256:781a2bdaea47324e7bab583e2263f21d257b0aee61ed51521a5be45f5f5081ef',
  postgres: 'postgres:16-alpine@sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea',
  redis   : 'redis:7-alpine@sha256:858f009f9709ce576febc734aa78b8f6d624b82571f9ddb6bda4377c833b3499',
]

// Email with the result; on failure the tail of the log inline + the full
// log attached, so nobody needs the (private, SSH-tunnel-only) Jenkins UI
// just to see why a build broke.
def notifyEmail(String status) {
  withCredentials([string(credentialsId: 'notify-email', variable: 'NOTIFY_TO')]) {
    def failed = status != 'SUCCESS'
    emailext(
      to: env.NOTIFY_TO,
      subject: "[${status}] ${env.JOB_NAME} #${env.BUILD_NUMBER}",
      mimeType: 'text/plain',
      attachLog: failed,
      compressLog: failed,
      // "${BUILD_LOG ...}" is an Email Extension token, expanded by the
      // plugin, not Groovy -- hence the single-quoted part.
      body: """Result: ${status}
Branch: ${env.BRANCH_NAME}${env.CHANGE_ID ? " (PR #${env.CHANGE_ID}: ${env.CHANGE_TITLE})" : ''}
Commit: ${env.GIT_COMMIT}
Build:  ${env.BUILD_URL}   (open through the SSH tunnel)
""" + (failed ? '\nLast 80 log lines:\n${BUILD_LOG, maxLines=80, escapeHtml=false}\n' : '')
    )
  }
}

pipeline {
  agent any

  // No triggers: Jenkins is private (no inbound webhook). The Multibranch
  // job's periodic scan (1 min, runbook §6) finds new commits/PRs and
  // starts builds; the `when` blocks below scope what runs where.

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '5'))
    timeout(time: 60, unit: 'MINUTES')
  }

  parameters {
    // Kill switches, default ON. Checked as `!= false` because the first
    // build of a new branch job has no params yet (guide A7 gotchas).
    booleanParam(name: 'ENABLE_SECURITY_SCAN', defaultValue: true,
      description: 'Gitleaks / Semgrep / Trivy / Checkov / ZAP stages')
    booleanParam(name: 'ENABLE_INTEGRATION_TESTS', defaultValue: true,
      description: 'Backend *.smoke.ts against a real Postgres + Redis + 3 Nest instances')
    // Default OFF until the credential exists on the controller.
    booleanParam(name: 'ENABLE_IMAGE_PUBLISH', defaultValue: false,
      description: 'Push the backend image to Docker Hub on main (needs dockerhub-token)')
    booleanParam(name: 'ENABLE_NOTIFICATIONS', defaultValue: false,
      description: 'Email SUCCESS/FAILURE (needs notify-email credential + SMTP, runbook §6)')
  }

  environment {
    IMAGE_NAME  = 'jajoji/auto-chess-backend' // Docker Hub, not GHCR (#286)
    IMAGE_TAG   = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : 'local'}"
    // Unique per job + build: BUILD_ID alone collides across branches, and
    // BUILD_TAG contains %2F for feature/x branches (guide A7 gotchas).
    CI_ID       = "${('ci-' + env.BUILD_TAG).replaceAll('[^A-Za-z0-9_.-]', '-').toLowerCase()}"
    PG_IMAGE    = "${IMAGES.postgres}"
    REDIS_IMAGE = "${IMAGES.redis}"
    ZAP_IMAGE   = "${IMAGES.zap}"
  }

  stages {
    // ── 1. Secrets — cheapest, every branch ─────────────────────────────
    stage('Security · Gitleaks') {
      when { expression { params.ENABLE_SECURITY_SCAN != false } }
      agent { docker { image IMAGES.gitleaks; args '--entrypoint='; reuseNode true } }
      // Tool containers run as the Jenkins uid, which has no home dir there.
      environment { HOME = '/tmp' }
      steps {
        // `git` (not the deprecated `detect`) scans full history.
        sh 'gitleaks git --config=.gitleaks.toml --redact --exit-code 1 --report-format sarif --report-path gitleaks.sarif .'
      }
      post { always { archiveArtifacts artifacts: 'gitleaks.sarif', allowEmptyArchive: true } }
    }

    // ── 2. Independent checks, in parallel ──────────────────────────────
    stage('PR checks') {
      failFast true
      parallel {
        stage('Backend · lint + unit test') {
          when { anyOf { branch 'dev'; branch 'main'; changeRequest target: 'dev'; changeRequest target: 'main' } }
          agent { docker { image IMAGES.node; reuseNode true } }
          environment { HOME = '/tmp'; npm_config_cache = "${env.WORKSPACE}/.cache/npm" }
          steps {
            dir('backend') {
              sh 'npm ci --no-audit --no-fund'
              sh 'npm run lint'
              sh 'npm run lint:eslint'
              sh 'npm run build'
              // Also leaves dist/ + devDeps for the integration smoke stage.
              sh 'npm run test:cov -- --ci'
            }
          }
          post {
            always {
              // jest-junit writes backend/reports/junit.xml (jest.config.js).
              junit testResults: 'backend/reports/junit.xml', allowEmptyResults: true
              archiveArtifacts artifacts: 'backend/coverage/**', allowEmptyArchive: true
              publishHTML(target: [
                reportDir: 'backend/coverage/lcov-report', reportFiles: 'index.html',
                reportName: 'Backend coverage', keepAll: true, alwaysLinkToLastBuild: true,
                allowMissing: true,
              ])
            }
          }
        }

        stage('Mobile · analyze + test') {
          when { anyOf { branch 'dev'; branch 'main'; changeRequest target: 'dev'; changeRequest target: 'main' } }
          // Root: the Flutter SDK in this image is root-owned and flutter
          // writes to its own cache. Ownership is handed back in post.
          agent { docker { image IMAGES.flutter; args '-u 0:0'; reuseNode true } }
          environment { HOME = '/tmp'; PUB_CACHE = "${env.WORKSPACE}/.cache/pub" }
          steps {
            dir('mobile') {
              sh 'flutter pub get'
              sh 'dart format --output=none --set-exit-if-changed .'
              sh 'flutter analyze'
              sh 'mkdir -p reports && flutter test --coverage --file-reporter json:reports/flutter-tests.json'
              // Same 84% floor as mobile-ci.yml (#274).
              sh 'bash ../ci/scripts/lcov-floor.sh coverage/lcov.info 84'
            }
          }
          post {
            always {
              dir('mobile') {
                sh '''
                  if [ -f reports/flutter-tests.json ]; then
                    dart pub global activate junitreport 2.0.2 >/dev/null
                    dart pub global run junitreport:tojunit \
                      --input reports/flutter-tests.json --output reports/flutter-junit.xml
                  fi
                '''
              }
              sh 'chown -R "$(stat -c %u:%g "$WORKSPACE")" mobile .cache'
              junit testResults: 'mobile/reports/flutter-junit.xml', allowEmptyResults: true
              archiveArtifacts artifacts: 'mobile/coverage/**', allowEmptyArchive: true
            }
          }
        }

        stage('Security · Semgrep') {
          when { expression { params.ENABLE_SECURITY_SCAN != false } }
          agent { docker { image IMAGES.semgrep; args '--entrypoint='; reuseNode true } }
          environment { HOME = '/tmp' }
          steps {
            // Community engine + registry ruleset only (no Pro rules).
            // The image sets SEMGREP_IN_DOCKER, which makes semgrep insist on
            // code mounted at /src; Jenkins mounts the workspace at its own
            // path, so drop the variable for this one command.
            sh 'env -u SEMGREP_IN_DOCKER semgrep scan --config=p/ci --error --metrics=off --disable-version-check --sarif-output=semgrep.sarif'
          }
          post { always { archiveArtifacts artifacts: 'semgrep.sarif', allowEmptyArchive: true } }
        }

        stage('Security · Trivy fs') {
          when { expression { params.ENABLE_SECURITY_SCAN != false } }
          agent { docker { image IMAGES.trivy; args '--entrypoint='; reuseNode true } }
          environment { HOME = '/tmp' }
          steps {
            // Blocks only fixable HIGH/CRITICAL (guide A4). Accepted risks
            // live in .trivyignore.yaml, each with a reason + expiry.
            sh '''
              trivy fs --cache-dir "$WORKSPACE/.cache/trivy" --timeout 15m --no-progress \
                --scanners vuln,secret,misconfig --severity HIGH,CRITICAL \
                --ignore-unfixed --exit-code 1 --ignorefile .trivyignore.yaml \
                --skip-dirs .cache,backend/node_modules,backend/dist,backend/coverage,mobile/.dart_tool,mobile/build \
                .
            '''
          }
        }

        stage('Security · Checkov') {
          when { expression { params.ENABLE_SECURITY_SCAN != false } }
          agent { docker { image IMAGES.checkov; args '--entrypoint='; reuseNode true } }
          environment { HOME = '/tmp' }
          steps {
            // No docker_compose framework exists in Checkov — the old
            // `--framework ...,docker_compose,...` made this stage fail on
            // every run. Skips are inline in the scanned file, with a reason.
            sh 'checkov -d . --framework dockerfile github_actions --compact --quiet --skip-path .cache --skip-path node_modules'
          }
        }
      }
    }

    // ── 3. Image: build → SBOM → scan (before anything is pushed) ───────
    stage('Backend image') {
      when { anyOf { branch 'dev'; branch 'main'; changeRequest target: 'dev'; changeRequest target: 'main' } }
      stages {
        stage('Backend · docker build') {
          steps {
            sh 'docker build -t "$IMAGE_NAME:$IMAGE_TAG" backend'
            // Scanners read the tarball — no docker.sock inside a scanner.
            sh 'docker save -o backend-image.tar "$IMAGE_NAME:$IMAGE_TAG"'
          }
        }
        stage('Security · SBOM + Trivy image') {
          agent { docker { image IMAGES.trivy; args '--entrypoint='; reuseNode true } }
          environment { HOME = '/tmp' }
          steps {
            sh '''
              trivy image --cache-dir "$WORKSPACE/.cache/trivy" --timeout 15m --no-progress \
                --input backend-image.tar --format cyclonedx --output sbom.cdx.json
            '''
            script {
              if (params.ENABLE_SECURITY_SCAN != false) {
                sh '''
                  trivy image --cache-dir "$WORKSPACE/.cache/trivy" --timeout 15m --no-progress \
                    --input backend-image.tar --severity HIGH,CRITICAL \
                    --ignore-unfixed --exit-code 1 --ignorefile .trivyignore.yaml
                '''
              }
            }
          }
          post { always { archiveArtifacts artifacts: 'sbom.cdx.json', allowEmptyArchive: true } }
        }
      }
    }

    // ── 4. Ephemeral stack: real infra, then DAST ───────────────────────
    stage('Ephemeral stack') {
      when {
        allOf {
          anyOf { branch 'dev'; branch 'main'; changeRequest target: 'dev'; changeRequest target: 'main' }
          expression { params.ENABLE_INTEGRATION_TESTS != false || params.ENABLE_SECURITY_SCAN != false }
        }
      }
      environment { IMAGE = "${env.IMAGE_NAME}:${env.IMAGE_TAG}" }
      stages {
        stage('Stack · up') {
          steps { sh 'bash ci/scripts/stack-up.sh' }
        }
        // Same suite as backend-ci.yml's backend-integration job (#283).
        stage('Backend · integration smoke') {
          when { expression { params.ENABLE_INTEGRATION_TESTS != false } }
          steps {
            script {
              // Runs the compiled smoke scripts from the Backend stage's
              // workspace (they need devDeps like socket.io-client, which
              // the production image doesn't ship), on the stack's network.
              docker.image(IMAGES.node).inside("--network ${env.CI_ID}-net") {
                dir('backend') {
                  withEnv(['HOME=/tmp',
                           'DATABASE_URL=postgres://ci:ci@postgres:5432/auto_chess',
                           'REDIS_URL=redis://redis:6379',
                           'HTTP_BASE=http://nest-1:3000']) {
                    sh 'npm run smoke:matchmaking'
                    sh 'npm run smoke:round-orchestrator:integration'
                    sh 'npm run smoke:shop:integration'
                    sh 'npm run smoke:ws'
                  }
                }
              }
            }
          }
        }
        stage('Security · ZAP') {
          when { expression { params.ENABLE_SECURITY_SCAN != false } }
          options { timeout(time: 20, unit: 'MINUTES') }
          steps { sh 'OUT_DIR=zap-reports bash ci/scripts/zap-scan.sh' }
          post {
            always {
              archiveArtifacts artifacts: 'zap-reports/**', allowEmptyArchive: true
              publishHTML(target: [
                reportDir: 'zap-reports', reportFiles: 'baseline.html,api.html',
                reportName: 'ZAP', keepAll: true, alwaysLinkToLastBuild: true, allowMissing: true,
              ])
            }
          }
        }
      }
      post {
        always {
          sh 'LOG_DIR=stack-logs bash ci/scripts/stack-down.sh'
          archiveArtifacts artifacts: 'stack-logs/**', allowEmptyArchive: true
        }
      }
    }

    // ── 5. Release: dev → main merge only ───────────────────────────────
    // Pushes the exact image built + scanned above — never rebuilds.
    stage('Backend · publish to Docker Hub') {
      when {
        allOf {
          branch 'main'
          not { changeRequest() }
          expression { params.ENABLE_IMAGE_PUBLISH == true }
        }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-token',
            usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_TOKEN')]) {
          sh '''
            echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin
            docker push "$IMAGE_NAME:$IMAGE_TAG"
            docker tag "$IMAGE_NAME:$IMAGE_TAG" "$IMAGE_NAME:latest"
            docker push "$IMAGE_NAME:latest"
            docker logout
          '''
        }
      }
    }
  }

  post {
    always {
      sh '''
        rm -f backend-image.tar
        docker rmi -f "$IMAGE_NAME:$IMAGE_TAG" "$IMAGE_NAME:latest" >/dev/null 2>&1 || true
        docker image prune -f >/dev/null 2>&1 || true
      '''
    }
    success {
      script { if (params.ENABLE_NOTIFICATIONS == true) { notifyEmail('SUCCESS') } }
    }
    unsuccessful {
      script { if (params.ENABLE_NOTIFICATIONS == true) { notifyEmail(currentBuild.currentResult) } }
    }
  }
}
