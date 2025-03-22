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
    stage('Set Variables') {
      steps {
        script {
          env.COMMIT_SHA = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
        }
      }
    }
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
              retry(3) {
                sh 'go install go.opentelemetry.io/collector/cmd/builder@latest'
                sh 'builder --verbose --config=otelcol-builder.yaml'
              }
              withCredentials([
                usernamePassword(
                  credentialsId: 'e86d9ebd-8b01-4f1f-8d2e-b871205023f7',
                  passwordVariable: 'REGISTRY_PASS',
                  usernameVariable: 'REGISTRY_USER'
                )
              ]) {
                sh 'podman login -u ${REGISTRY_USER} -p ${REGISTRY_PASS} slocos.io'
              }
              script {
                def cache = "slocos.io/cache/opentelemetry-collector-buildcache:${env.ARCH}-${env.COMMIT_SHA}"
                def platform = "linux/${env.ARCH}"
                sh "podman build --platform ${platform} -t ${cache} -f Containerfile ."
                sh "podman push ${cache}"
              }
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
            // Container image name components
            def main_base = "slocos.io/otel/opentelemetry-collector"
            def main_tag = "latest"
            def main = "${main_base}:${main_tag}"
            
            // Manifest command
            def manifest = "podman manifest create ${main}"
            ['amd64', 'arm64'].each {

              // Arch-specific image name components
              def target_tag = "${it}-${main_tag}"
              def target = "${main_base}:${target_tag}"
              def cache =  "slocos.io/cache/opentelemetry-collector-buildcache:${it}-${env.COMMIT_SHA}"

              // Pull, tag, push
              sh "podman pull ${cache}"
              sh "podman tag ${cache} ${target}"
              sh "podman push ${target}"

              // Sign the image
              def digest = sh(returnStdout: true, script: "podman image inspect --format '{{.Digest}}' ${target}").trim()
              sh "cosign sign -y -r \
                --upload=true \
                --registry-username=${env.REGISTRY_USER} \
                --registry-password=${env.REGISTRY_PASS} \
                --record-creation-timestamp=true \
                --tlog-upload=true \
                --key hashivault://cosign \
                ${main_base}@${digest}"

              // Add to manifest
              manifest += " ${target}"
            }

            // Push the manifest
            sh "${manifest}"
            sh "podman manifest push --all ${main}"

            // Sign the manifest
            def digest = sh(returnStdout: true, script: "podman image inspect --format '{{.Digest}}' ${main}").trim()
            sh "cosign sign -y -r \
                --upload=true \
                --registry-username=${env.REGISTRY_USER} \
                --registry-password=${env.REGISTRY_PASS} \
                --record-creation-timestamp=true \
                --tlog-upload=true \
                --key hashivault://cosign \
                ${main_base}@${digest}"
          }
        }
      }
    }
  }
}
// vim: ft=groovy
