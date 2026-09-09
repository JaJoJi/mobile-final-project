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
//      auto-discovers this Jenkinsfile per branch/PR.
//   3. Add credentials (Jenkins > Credentials):
//        - `ghcr-token`      (GHCR push, Kind: Username+password / PAT)
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
      description: 'Build + push the backend image to GHCR (needs the ghcr-token credential)')
    booleanParam(name: 'ENABLE_NOTIFICATIONS', defaultValue: false,
      description: 'Post build result to Discord (needs the discord-webhook credential)')
  }

  environment {
    NODE_VERSION   = '22'
    IMAGE_NAME     = 'ghcr.io/jajoji/auto_chess-backend'
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
          // TODO on activation: add the `jest-junit` devDependency + a
          // `reporters: ['default', 'jest-junit']` entry to jest.config.js,
          // then switch this to `junit testResults: 'backend/junit.xml'`
          // (no jest-junit installed yet, so there's nothing to publish).
          archiveArtifacts artifacts: 'backend/coverage/**', allowEmptyArchive: true
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

    // ── Security · dependency audit + secret scan (P3-DO-07) ──────────
    // Source-level checks; no image needed, so they run before the build.
    // The GitHub side is the real gate (codeql.yml, gitleaks.yml,
    // backend-ci.yml `npm audit`); this mirrors it for the parked Jenkins
    // pipeline (#190) so the two don't drift.

    stage('Security · audit + secrets') {
      steps {
        dir('backend') { sh 'npm audit --audit-level=high' }
        sh 'gitleaks detect --source . --config .gitleaks.toml --redact --exit-code 1'
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

    // Image scan — after the build, before publish. Fixable HIGH/CRITICAL
    // fails the pipeline so a vulnerable image is never pushed.
    stage('Security · image scan') {
      steps {
        sh "trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed --ignorefile .trivyignore ${IMAGE_NAME}:${IMAGE_TAG}"
      }
    }

    stage('Backend · publish to GHCR') {
      when { expression { return params.ENABLE_IMAGE_PUBLISH } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'ghcr-token',
            usernameVariable: 'GHCR_USER', passwordVariable: 'GHCR_TOKEN')]) {
          sh '''
            echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
            docker push ${IMAGE_NAME}:${IMAGE_TAG}
            if [ "$BRANCH_NAME" = "main" ]; then
              docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest
              docker push ${IMAGE_NAME}:latest
            fi
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
