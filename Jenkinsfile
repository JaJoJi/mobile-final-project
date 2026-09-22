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
    // Ordered cheapest/fastest-first so a fail-fast doesn't wait behind
    // the image build. Trivy's IMAGE scan (needs a built image) is
    // deliberately not here — that's tied to the Release stage in #220;
    // this Trivy pass is filesystem-only (SCA + secrets + misconfig).
    stage('Scan · Gitleaks') {
      steps {
        sh '''
          docker run --rm -v "$WORKSPACE:/repo" zricethezav/gitleaks:latest \
            detect --source=/repo --redact --report-format junit \
            --report-path /repo/gitleaks-report.xml
        '''
      }
      post {
        always {
          junit testResults: 'gitleaks-report.xml', allowEmptyResults: true
        }
      }
    }

    stage('Scan · Checkov') {
      steps {
        sh '''
          docker run --rm -v "$WORKSPACE:/repo" -w /repo bridgecrew/checkov:latest \
            --directory /repo --config-file /repo/.checkov.yml \
            --output junitxml --output-file-path checkov-out
          # checkov writes checkov-out/ as a directory (results_junitxml.xml
          # inside it), not a plain file at that path — verified, not assumed.
        '''
      }
      post {
        always {
          junit testResults: 'checkov-out/results_junitxml.xml', allowEmptyResults: true
        }
      }
    }

    stage('Scan · Semgrep') {
      steps {
        sh '''
          docker run --rm -v "$WORKSPACE:/src" semgrep/semgrep:latest \
            semgrep scan --config auto --severity ERROR \
            --exclude "mobile/.dart_tool" --exclude "**/node_modules" \
            --junit-xml-output=/src/semgrep-report.xml /src
        '''
      }
      post {
        always {
          junit testResults: 'semgrep-report.xml', allowEmptyResults: true
        }
      }
    }

    // SCA/IaC/secrets in one filesystem pass. Soft-fail, not blocking:
    // real HIGH/CRITICAL CVEs currently exist in transitive deps
    // (lodash/multer/tar/js-yaml under backend's dependency tree,
    // verified via a real scan) that need a dependency-upgrade pass —
    // separate work from standing up this stage. Report is archived so
    // the findings stay visible instead of silently passing.
    stage('Scan · Trivy (fs)') {
      steps {
        catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
          sh '''
            docker run --rm -v "$WORKSPACE:/repo" aquasec/trivy:latest fs \
              --scanners vuln,secret,misconfig --severity HIGH,CRITICAL \
              --timeout 8m --exit-code 1 \
              --skip-dirs "**/node_modules,**/.dart_tool,**/.git,**/build,mobile/build,backend/dist,backend/coverage" \
              --format template --template "@/contrib/junit.tpl" \
              --output /repo/trivy-report.xml \
              /repo
          '''
        }
      }
      post {
        always {
          junit testResults: 'trivy-report.xml', allowEmptyResults: true
        }
      }
    }

    // Ephemeral in-job target: build + run just enough of the stack
    // (Postgres, Redis, the backend image) to give ZAP something to hit,
    // then tear it down — no permanent staging environment. Baseline
    // scan is passive (spider + passive rules only, no active attack),
    // so it's safe against a real ephemeral instance.
    stage('Scan · ZAP baseline') {
      steps {
        dir('backend') { sh "docker build -t ${IMAGE_NAME}:scan-${env.BUILD_ID} ." }
        sh '''
          docker network create zap-scan-$BUILD_ID
          docker run -d --rm --name zap-pg-$BUILD_ID --network zap-scan-$BUILD_ID \
            -e POSTGRES_USER=ci -e POSTGRES_PASSWORD=ci -e POSTGRES_DB=ci \
            postgres:16-alpine
          docker run -d --rm --name zap-redis-$BUILD_ID --network zap-scan-$BUILD_ID \
            redis:7-alpine
          sleep 5
          docker run -d --rm --name zap-backend-$BUILD_ID --network zap-scan-$BUILD_ID \
            -e NODE_ENV=production \
            -e JWT_SECRET=ci_jwt_secret_not_a_real_secret_0123456789abcdef \
            -e JWT_ACCESS_TTL=7d -e JWT_REFRESH_TTL=30d \
            -e DATABASE_URL=postgres://ci:ci@zap-pg-$BUILD_ID:5432/ci \
            -e REDIS_URL=redis://zap-redis-$BUILD_ID:6379 \
            ${IMAGE_NAME}:scan-$BUILD_ID
          sleep 5
        '''
        catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
          sh '''
            docker run --rm --network zap-scan-$BUILD_ID -v "$WORKSPACE:/zap/wrk" \
              zaproxy/zap-stable:latest zap-baseline.py \
              -t http://zap-backend-$BUILD_ID:3000 \
              -r zap-report.html -J zap-report.json -I
          '''
        }
      }
      post {
        always {
          sh '''
            docker rm -f zap-backend-$BUILD_ID zap-pg-$BUILD_ID zap-redis-$BUILD_ID || true
            docker network rm zap-scan-$BUILD_ID || true
            docker rmi ${IMAGE_NAME}:scan-$BUILD_ID || true
          '''
          archiveArtifacts artifacts: 'zap-report.html,zap-report.json', allowEmptyArchive: true
          publishHTML(target: [
            reportDir: '.',
            reportFiles: 'zap-report.html',
            reportName: 'ZAP baseline',
            keepAll: true,
            alwaysLinkToLastBuild: true,
          ])
        }
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
