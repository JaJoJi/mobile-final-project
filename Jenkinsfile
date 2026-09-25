// Jenkins declarative pipeline for mobile-final-project.
//
// STATUS: parked. No self-hosted Jenkins runner exists yet — GitHub Actions
// (.github/workflows/backend-ci.yml, mobile-ci.yml) remains the pipeline
// that actually runs on every PR. This file exists so the toolchain design
// is complete on paper and ready to activate the moment a runner exists;
// it does not replace or disable the GitHub Actions workflows.
//
// To activate:
//   1. Stand up a Jenkins controller + at least one agent with Docker
//      available (`docker` in PATH, socket mounted or DinD).
//   2. Create a Multibranch Pipeline job pointing at this repo — Jenkins
//      auto-discovers this Jenkinsfile per branch/PR. Install the
//      "HTML Publisher" plugin too (JUnit is core) -- see
//      docs/08-runbook.md §6 for the full controller setup checklist.
//   3. Add credentials (Jenkins > Credentials):
//        - `dockerhub-token` (Docker Hub push, Kind: Username+password / PAT
//                             -- devops-toolchain.md §3, not GHCR)
//        - `discord-webhook` (build notifications, Kind: Secret text)
//   4. Flip the `params.ENABLE_*` defaults below once the matching
//      infra/credential exists. Everything is gated so a fresh Jenkins
//      with none of that configured still runs green (build + unit test
//      only), instead of failing on a missing tool.
//
// Stage set mirrors + extends the GitHub Actions CI (see the devops
// toolchain review — P3-DO-08): this pipeline additionally spins up real
// Postgres + Redis to run the backend's `*.smoke.ts` integration suite,
// which GH Actions currently skips.

pipeline {
  agent any

  triggers {
    // devops-toolchain.md §1: GitHub push webhook, no GitHub Actions
    // involved. Combined with the Multibranch Pipeline job's own branch/
    // PR discovery (configured at the Jenkins job level, not here) this
    // gives the agreed scope: check every PR into dev, check again on
    // dev -> main merges (Push stage below only fires on main).
    githubPush()
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 30, unit: 'MINUTES')
  }

  parameters {
    // Each defaults OFF until the backing infra/credential actually
    // exists — see the activation notes above.
    booleanParam(name: 'ENABLE_INTEGRATION_TESTS', defaultValue: false,
      description: 'Run backend *.smoke.ts against real Postgres+Redis (needs Docker on the agent)')
    booleanParam(name: 'ENABLE_IMAGE_PUBLISH', defaultValue: false,
      description: 'Build + push the backend image to Docker Hub (needs the dockerhub-token credential)')
    booleanParam(name: 'ENABLE_NOTIFICATIONS', defaultValue: false,
      description: 'Post build result to Discord (needs the discord-webhook credential)')
    booleanParam(name: 'ENABLE_SECURITY_SCAN', defaultValue: false,
      description: 'Run Gitleaks/Semgrep/Trivy/Checkov/ZAP security stages (needs docker on the Jenkins host — devops-toolchain.md §2)')
  }

  environment {
    NODE_VERSION   = '22'
    IMAGE_NAME     = 'jajoji/auto-chess-backend' // Docker Hub (devops-toolchain.md §3), not GHCR
    IMAGE_TAG      = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : 'local'}"
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    // ── Backend ──────────────────────────────────────────────────────

    stage('Backend · install') {
      steps { dir('backend') { sh 'npm ci' } }
    }

    stage('Backend · lint + build') {
      parallel {
        stage('lint (typecheck)') {
          steps { dir('backend') { sh 'npm run lint' } }
        }
        stage('lint (eslint)') {
          steps { dir('backend') { sh 'npm run lint:eslint' } }
        }
        stage('build') {
          steps { dir('backend') { sh 'npm run build' } }
        }
      }
    }

    stage('Backend · unit test + coverage') {
      steps {
        dir('backend') { sh 'npm run test:cov -- --ci' }
      }
      post {
        always {
          // P3-DO-14: jest-junit + jest.config.js's `reporters` entry
          // write backend/reports/junit.xml -- verified for real
          // (126 tests, real XML written, checked its content).
          junit testResults: 'backend/reports/junit.xml', allowEmptyResults: true
          archiveArtifacts artifacts: 'backend/coverage/**', allowEmptyArchive: true
          publishHTML(target: [
            reportDir: 'backend/coverage/lcov-report',
            reportFiles: 'index.html',
            reportName: 'Backend coverage',
            keepAll: true,
            alwaysLinkToLastBuild: true,
          ])
        }
      }
    }

    // Real Postgres + Redis, not mocks — exercises the *.smoke.ts
    // integration suite (matchmaking, round-orchestrator, pubsub, ws)
    // that GitHub Actions' backend-ci.yml deliberately skips.
    stage('Backend · integration smoke') {
      when { expression { return params.ENABLE_INTEGRATION_TESTS } }
      steps {
        dir('backend') {
          sh '''
            docker run -d --rm --name jenkins-pg-$BUILD_ID \
              -e POSTGRES_USER=ci -e POSTGRES_PASSWORD=ci -e POSTGRES_DB=ci \
              -p 0:5432 postgres:16-alpine
            docker run -d --rm --name jenkins-redis-$BUILD_ID -p 0:6379 redis:7-alpine
            # TODO once enabled: resolve the mapped host ports, export
            # DATABASE_URL / REDIS_URL, run migrations, then:
            npm run smoke:matchmaking
            npm run smoke:round-orchestrator:integration
            npm run smoke:shop:integration
            npm run smoke:ws
          '''
        }
      }
      post {
        always {
          sh 'docker rm -f jenkins-pg-$BUILD_ID jenkins-redis-$BUILD_ID || true'
        }
      }
    }

    // ── Mobile ───────────────────────────────────────────────────────

    stage('Mobile · analyze + test') {
      steps {
        dir('mobile') {
          sh 'flutter pub get'
          sh 'dart format --output=none --set-exit-if-changed .'
          sh 'flutter analyze'
          sh 'flutter test'
        }
      }
    }

    // ── Security scan (P3-DO-15, devops-toolchain.md §2) ───────────────
    // Gitleaks → Semgrep → Trivy (deps/IaC/secrets) → Checkov, cheapest
    // first, all ahead of the image build. Each tool runs as a
    // throwaway container on the built-in node — no daemon, no idle
    // RAM cost while ENABLE_SECURITY_SCAN is off (the default until
    // Jenkins is actually live — see the file header).

    stage('Security · Gitleaks') {
      when { expression { return params.ENABLE_SECURITY_SCAN } }
      steps {
        sh '''
          docker run --rm -v "$WORKSPACE:/repo" zricethezav/gitleaks:latest \
            detect --source=/repo --config=/repo/.gitleaks.toml --redact --exit-code 1
        '''
      }
    }

    stage('Security · Semgrep') {
      when { expression { return params.ENABLE_SECURITY_SCAN } }
      steps {
        // Free community engine only — Pro cross-file rules are paid,
        // not used (devops-toolchain.md §2).
        sh '''
          docker run --rm -v "$WORKSPACE:/src" returntocorp/semgrep semgrep scan \
            --config=p/ci --error --metrics=off /src
        '''
      }
    }

    stage('Security · Trivy (deps + IaC + secrets)') {
      when { expression { return params.ENABLE_SECURITY_SCAN } }
      steps {
        sh '''
          docker run --rm -v "$WORKSPACE:/repo" aquasec/trivy:latest fs \
            --scanners vuln,secret,misconfig --severity HIGH,CRITICAL --exit-code 1 \
            --ignorefile /repo/.trivyignore /repo
        '''
      }
    }

    stage('Security · Checkov') {
      when { expression { return params.ENABLE_SECURITY_SCAN } }
      steps {
        sh '''
          docker run --rm -v "$WORKSPACE:/repo" bridgecrew/checkov:latest \
            -d /repo --framework dockerfile,docker_compose,github_actions --compact --quiet
        '''
      }
    }

    // ── Package / publish ────────────────────────────────────────────

    stage('Backend · docker build') {
      steps {
        dir('backend') {
          sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
        }
      }
    }

    // Image scan needs the built image, so it runs here rather than
    // with the other Security stages above (devops-toolchain.md §2
    // design note) — still gates the publish step below.
    stage('Security · Trivy (image)') {
      when { expression { return params.ENABLE_SECURITY_SCAN } }
      steps {
        sh """
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v \$WORKSPACE:/repo aquasec/trivy:latest \
            image --severity HIGH,CRITICAL --exit-code 1 --ignorefile /repo/.trivyignore ${IMAGE_NAME}:${IMAGE_TAG}
        """
      }
    }

    // Ephemeral OWASP ZAP baseline: spin up the just-built image + real
    // Postgres/Redis on a throwaway docker network, scan, tear down.
    // No permanent staging environment (devops-toolchain.md §2).
    stage('Security · ZAP baseline (ephemeral)') {
      when { expression { return params.ENABLE_SECURITY_SCAN } }
      steps {
        sh '''
          NET="zap-net-$BUILD_ID"
          docker network create "$NET"
          docker run -d --rm --network "$NET" --name zap-pg-$BUILD_ID \
            -e POSTGRES_USER=ci -e POSTGRES_PASSWORD=ci -e POSTGRES_DB=ci \
            postgres:16-alpine
          docker run -d --rm --network "$NET" --name zap-redis-$BUILD_ID redis:7-alpine
          docker run -d --rm --network "$NET" --name zap-app-$BUILD_ID \
            -e DATABASE_URL=postgres://ci:ci@zap-pg-$BUILD_ID:5432/ci \
            -e REDIS_URL=redis://zap-redis-$BUILD_ID:6379 \
            -e JWT_SECRET=zap_ephemeral_not_a_real_secret \
            -e JWT_ACCESS_TTL=7d -e JWT_REFRESH_TTL=30d \
            -e RUN_MIGRATIONS=true -e NODE_ENV=test -e NEST_PORT=3000 \
            ${IMAGE_NAME}:${IMAGE_TAG}
          for i in $(seq 1 30); do
            docker exec zap-app-$BUILD_ID wget -qO- http://localhost:3000/health/ready >/dev/null 2>&1 && break
            sleep 1
          done
          # TODO on activation: tune false positives via a ZAP rules
          # file (-c zap.conf) once a real baseline report exists to
          # review — starting strict (no rule exceptions) on purpose.
          docker run --rm --network "$NET" -v "$WORKSPACE/backend:/zap/wrk" \
            ghcr.io/zaproxy/zaproxy:stable zap-baseline.py \
            -t http://zap-app-$BUILD_ID:3000 -r zap-report.html
        '''
      }
      post {
        always {
          sh '''
            docker rm -f zap-app-$BUILD_ID zap-pg-$BUILD_ID zap-redis-$BUILD_ID >/dev/null 2>&1 || true
            docker network rm zap-net-$BUILD_ID >/dev/null 2>&1 || true
          '''
          archiveArtifacts artifacts: 'backend/zap-report.html', allowEmptyArchive: true
        }
      }
    }

    // Release only fires on dev -> main merges (agreed scope: Jenkins
    // checks every PR into dev, checks again + releases on dev -> main).
    // Pushes the exact IMAGE_NAME:IMAGE_TAG already built + scanned
    // above -- never rebuilds, so "build once, deploy anywhere".
    stage('Backend · publish to Docker Hub') {
      when {
        allOf {
          expression { return params.ENABLE_IMAGE_PUBLISH }
          branch 'main'
        }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-token',
            usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_TOKEN')]) {
          sh '''
            echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin
            docker push ${IMAGE_NAME}:${IMAGE_TAG}
            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest
            docker push ${IMAGE_NAME}:latest
          '''
        }
      }
    }
  }

  post {
    always {
      sh 'docker image prune -f || true'
    }
    // P3-DO-11 style notification hook — same shape as the alerting
    // channel proposed for Grafana, so both stages land in one place.
    unsuccessful {
      script {
        if (params.ENABLE_NOTIFICATIONS) {
          withCredentials([string(credentialsId: 'discord-webhook', variable: 'WEBHOOK')]) {
            sh """
              curl -sf -X POST -H 'Content-Type: application/json' \
                -d '{"content":"❌ Jenkins build failed: ${env.JOB_NAME} #${env.BUILD_NUMBER} — ${env.BUILD_URL}"}' \
                "$WEBHOOK"
            """
          }
        }
      }
    }
  }
}
