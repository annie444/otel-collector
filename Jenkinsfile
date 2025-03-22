pipeline {
  agent {
    label 'amd64-agent'
  }
  environment {
    VAULT_ADDR = 'https://vault.jpeg.gay'
    VAULT_ROLE_ID = credentials('031dfe05-38de-43ba-b01d-c6c3d0387596')
    VAULT_SECRET_ID = credentials('e722c574-f907-4cd2-8336-d7cabae112eb')
  }
  stages {
    stage('Build Multi-Arch Image') {
      matrix {
        axes {
          axis {
            name 'ARCH'
            values 'amd64', 'arm64'
          }
        }
        agent {
          label "${ARCH}-agent"
        }
        stages {
          stage('Podman Build') {
            steps {
              echo "Building for ${ARCH}"
              sh 'go install go.opentelemetry.io/collector/cmd/builder@latest'
              retry(3) {
                sh 'builder --verbose --config=otelcol-builder.yaml'
              }
              sh 'podman build --platform "linux/${ARCH}" -t "slocos.io/otel/opentelemetry-collector:${ARCH}-latest" -f Containerfile .'
            }
          }
        }
      }
    }
    stage('Bundle, Sign, and Push') {
      steps {
        withCredentials([
          usernamePassword(
            credentialsId: 'e86d9ebd-8b01-4f1f-8d2e-b871205023f7',
            passwordVariable: 'REGISTRY_PASS',
            usernameVariable: 'REGISTRY_USER'
          )
        ]) {
          sh 'podman login -u ${REGISTRY_USER} -p ${REGISTRY_PASS} slocos.io'
          script {
            def manifest = "podman manifest create slocos.io/otel/opentelemetry-collector:latest"
            ['amd64', 'arm64'].each {
              manifest += " slocos.io/otel/opentelemetry-collector:${it}-latest"
            }
            sh "${manifest}"
            sh "podman manifest push --all slocos.io/otel/opentelemetry-collector:latest"
            def digest = sh(returnStdout: true, script: "podman image inspect --format '{{.Digest}}' slocos.io/otel/opentelemetry-collector:latest").trim()
            sh "cosign sign -y -r \
                --upload=true \
                --registry-username=${env.REGISTRY_USER} \
                --registry-password=${env.REGISTRY_PASS} \
                --record-creation-timestamp=true \
                --tlog-upload=true \
                --key hashivault://cosign \
                slocos.io/otel/opentelemetry-collector:latest@${digest}"
          }
        }
      }
    }
  }
}
// vim: ft=groovy
