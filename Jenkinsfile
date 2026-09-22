// Jenkins declarative pipeline for mobile-final-project. (P3-DO-14)
//
// Un-parked version of #190's draft: a real Jenkins controller + GitHub
// webhook now exist, so this is the sole CI/CD engine — GitHub Actions
// is retired, no more ENABLE_* flags standing in for a fallback pipeline.
// Runs on the controller's built-in node (no separate Docker agent —
// devops-toolchain.md §1), as a Multibranch Pipeline job so this file is
// auto-discovered per branch/PR.
//
// Stage shape matches devops-toolchain.md: Scan -> Build -> Push -> CD.
// Scan (#219), Push (#220) and CD (#221) are separate backlog issues —
// each is a stub here until its issue lands the real steps.
//
// Controller setup (install, webhook plugin, credentials store, HTML
// Publisher plugin) isn't repo-tracked — see docs/08-runbook.md.

pipeline {
  agent any

  triggers {
    githubPush()
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 30, unit: 'MINUTES')
  }

  parameters {
    // *.smoke.ts integration suite needs Postgres/Redis env wiring
    // (mapped ports -> DATABASE_URL/REDIS_URL, migrations) that isn't
    // finished yet — separate from the ENABLE_* fallback-safety flags
    // this file used to carry. Off by default until that wiring lands.
    booleanParam(name: 'RUN_INTEGRATION_SMOKE', defaultValue: false,
      description: 'Run backend *.smoke.ts against real Postgres+Redis — needs env wiring, see stage TODO')
  }

  environment {
    NODE_VERSION = '22'
    IMAGE_NAME   = 'jajoji/auto-chess-backend' // Docker Hub (devops-toolchain.md §3), not GHCR
    IMAGE_TAG    = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : 'local'}"
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    // ── Scan ─────────────────────────────────────────────────────────
    stage('Scan') {
      steps {
        echo 'TODO(#219): Gitleaks + Semgrep + Trivy + Checkov + ephemeral ZAP'
      }
    }

    // ── Build / Test — backend ──────────────────────────────────────
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
    // that GitHub Actions' backend-ci.yml used to skip.
    stage('Backend · integration smoke') {
      when { expression { return params.RUN_INTEGRATION_SMOKE } }
      steps {
        dir('backend') {
          sh '''
            docker run -d --rm --name jenkins-pg-$BUILD_ID \
              -e POSTGRES_USER=ci -e POSTGRES_PASSWORD=ci -e POSTGRES_DB=ci \
              -p 0:5432 postgres:16-alpine
            docker run -d --rm --name jenkins-redis-$BUILD_ID -p 0:6379 redis:7-alpine
            # TODO: resolve the mapped host ports, export
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

    // ── Build / Test — mobile ────────────────────────────────────────
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

    stage('Backend · docker build') {
      steps {
        dir('backend') {
          sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
        }
      }
    }

    // ── Push ─────────────────────────────────────────────────────────
    stage('Push') {
      when { branch 'main' }
      steps {
        echo 'TODO(#220): docker login (Docker Hub) + tag + push'
      }
    }

    // ── CD ───────────────────────────────────────────────────────────
    stage('Deploy') {
      when { branch 'main' }
      steps {
        echo 'TODO(#221): ansible-playbook deploy over SSH'
      }
    }
  }

  post {
    always {
      sh 'docker image prune -f || true'
    }
  }
}
