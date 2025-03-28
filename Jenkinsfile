pipeline {
  triggers {
    githubPush()
    pollSCM ignorePostCommitHooks: true, scmpoll_spec: 'H */2 * * *'
  }

  agent {
    label 'amd64-agent'
  }

  options {
    ansiColor('xterm')
    buildDiscarder logRotator(artifactDaysToKeepStr: '60', artifactNumToKeepStr: '10', daysToKeepStr: '60', numToKeepStr: '10')
    durabilityHint 'MAX_SURVIVABILITY'
    parallelsAlwaysFailFast()
    quietPeriod 5
    retry(conditions: [nonresumable(), agent()], count: 2)
    timestamps()
  }

  environment {
    VAULT_ADDR = 'https://vault.jpeg.gay'
    VAULT_ROLE_ID = credentials('031dfe05-38de-43ba-b01d-c6c3d0387596')
    VAULT_SECRET_ID = credentials('e722c574-f907-4cd2-8336-d7cabae112eb')
    REGISTRY = "slocos.io"
    PROJECT = "otel"
    IMAGE = "opentelemetry-collector"
    IS_ROLLING = "false"
    IS_RELEASE = "false"
    IS_PR = "false"
    IS_DEV = "false"
    RELEASE_EMAIL = "ops@jpeg.gay"
    DEV_EMAIL = "devops@jpeg.gay"
    PRIMARY_BRANCH = "main"
  }

  stages {
    stage('Set Variables') {
      steps {
        script {
          env.COMMIT_SHA = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
          if (env.BRANCH_NAME == env.PRIMARY_BRANCH) {
            env.CACHE_PROJECT = "cache"
            env.TAG = "latest"
            env.CI = "true"
            env.IS_ROLLING = "true"
          } else if (env.BRANCH_NAME ==~ /^release-.*$/) {
            env.CACHE_PROJECT = "cache"
            env.TAG = env.BRANCH_NAME
            env.CI = "true"
            env.IS_RELEASE = "true"
          } else if (env.CHANGE_TARGET == env.PRIMARY_BRANCH) {
            env.CACHE_PROJECT = "pr"
            env.TAG = "${env.BRANCH_NAME}-${env.CHANGE_BRANCH}-${env.COMMIT_SHA}"
            env.CI = "true"
            env.IS_PR = "true"
          } else {
            env.CACHE_PROJECT = "dev"
            env.TAG = "${env.BRANCH_NAME}-${env.COMMIT_SHA}"
            env.IS_DEV = "true"
          }
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
              script {
                def downTime = 1
                retry(3) {
                  downTime = downTime * 2
                  sh 'go install go.opentelemetry.io/collector/cmd/builder@latest'
                  sh 'builder --verbose --config=otelcol-builder.yaml'
                  sleep downTime
                }
                archiveArtifacts artifacts: 'otelcol',
                    allowEmptyArchive: true,
                    fingerprint: true,
                    onlyIfSuccessful: true,
                    followSymlinks: true
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
                def cache = "${env.REGISTRY}/${env.CACHE_PROJECT}/${env.IMAGE}-buildcache:${env.ARCH}-${env.COMMIT_SHA}"
                def platform = "linux/${env.ARCH}"
                sh "podman build --platform ${platform} --tag ${cache} --file Containerfile ."
                sh "podman push ${cache}"
              }
            }
          }
        }
      }
    }

    stage('Bundle, Sign, and Push') {
      when {
        environment ignoreCase: true, name: 'CI', value: 'true'
      }
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
            def main_base = "${env.REGISTRY}/${env.PROJECT}/${env.IMAGE}"
            def main = "${main_base}:${env.TAG}"
            
            // Manifest command
            def manifest = "podman manifest create ${main}"
            ['amd64', 'arm64'].each {

              // Arch-specific image name components
              def target_tag = "${it}-${env.TAG}"
              def target = "${main_base}:${target_tag}"
              def cache = "${env.REGISTRY}/${env.CACHE_PROJECT}/${env.IMAGE}-buildcache:${it}-${env.COMMIT_SHA}"

              // Pull, tag, push
              sh "podman pull ${cache}"
              sh "podman tag ${cache} ${target}"
              sh "podman push ${target}"

              // Sign the image
              def downTime = 1
              retry(3) {
                downTime = downTime * 2
                def digest = sh(returnStdout: true, script: "skopeo inspect --format '{{.Digest}}' docker://${target}").trim()
                env.CONTAINER_DIGEST = "${main_base}@${digest}"
                sh '''
                    export VAULT_ADDR="${VAULT_ADDR}"
                    export VAULT_TOKEN=$(vault write -field=token auth/approle/login role_id=${VAULT_ROLE_ID} secret_id=${VAULT_SECRET_ID})
                    cosign sign -y -r \
                      --upload=true \
                      --registry-username=${REGISTRY_USER} \
                      --registry-password=${REGISTRY_PASS} \
                      --key hashivault://cosign \
                      ${CONTAINER_DIGEST}
                    '''
                sleep downTime
              }

              // Add to manifest
              manifest += " ${target}"
            }

            // Push the manifest
            sh "${manifest}"
            sh "podman manifest push --all ${main} docker://${main}"

            // Sign the manifest
            def digest = sh(returnStdout: true, script: "skopeo inspect --format '{{.Digest}}' docker://${main}").trim()
            env.CONTAINER_DIGEST = "${main_base}@${digest}"
            sh '''
                export VAULT_ADDR="${VAULT_ADDR}"
                export VAULT_TOKEN=$(vault write -field=token auth/approle/login role_id=${VAULT_ROLE_ID} secret_id=${VAULT_SECRET_ID})
                cosign sign -y -r \
                  --upload=true \
                  --registry-username=${REGISTRY_USER} \
                  --registry-password=${REGISTRY_PASS} \
                  --record-creation-timestamp=true \
                  --tlog-upload=true \
                  --key hashivault://cosign \
                  ${CONTAINER_DIGEST}
                '''
          }
        }
      }
    }
  }

  post {

    unstable {
      echo "Unstable!"
      script {
        if (env.IS_ROLLING) {
          emailext(
            subject: "Unstable: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Unstable! ${env.BUILD_URL}",
            recipientProviders: [contributor(), developers(), requestor()],
            attachLog: true,
            compressLog: true,
            replyTo: env.RELEASE_EMAIL,
            saveOutput: false
          )
        } else if (env.IS_RELEASE) {
          emailext(
            subject: "Unstable: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Unstable! ${env.BUILD_URL}",
            recipientProviders: [previous()],
            attachLog: true,
            compressLog: true,
            replyTo: env.RELEASE_EMAIL,
            saveOutput: false
          )
        } else if (env.IS_PR) {
          emailext(
            subject: "Unstable: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Unstable! ${env.BUILD_URL}",
            recipientProviders: [developers(), requestor()],
            attachLog: true,
            compressLog: true,
            replyTo: env.DEV_EMAIL,
            saveOutput: false
          )
        } else if (env.IS_DEV) {
          emailext(
            subject: "Unstable: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Unstable! ${env.BUILD_URL}",
            recipientProviders: [developers(), requestor()],
            attachLog: true,
            compressLog: true,
            replyTo: env.DEV_EMAIL,
            saveOutput: false
          )
        } else {
          echo "Unknown build type"
        }
      }
    }

    success {
      echo "Success!"
      script {
        if (env.IS_ROLLING) {
          emailext(
            subject: "Success: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Success! ${env.BUILD_URL}",
            recipientProviders: [contributor(), developers(), requestor()],
            attachLog: true,
            compressLog: true,
            replyTo: env.RELEASE_EMAIL,
            saveOutput: false
          )
        } else if (env.IS_RELEASE) {
          emailext(
            subject: "Success: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Success! ${env.BUILD_URL}",
            recipientProviders: [previous()],
            attachLog: true,
            compressLog: true,
            replyTo: env.RELEASE_EMAIL,
            saveOutput: true
          )
        } else if (env.IS_PR) {
          emailext(
            subject: "Success: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Success! ${env.BUILD_URL}",
            recipientProviders: [developers(), requestor()],
            attachLog: true,
            compressLog: true,
            replyTo: env.DEV_EMAIL,
            saveOutput: false
          )
        } else if (env.IS_DEV) {
          emailext(
            subject: "Success: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Success! ${env.BUILD_URL}",
            recipientProviders: [developers(), requestor()],
            attachLog: true,
            compressLog: true,
            replyTo: env.DEV_EMAIL,
            saveOutput: false
          )
        } else {
          echo "Unknown build type"
        }
      }
    }

    aborted {
      echo "Build Aborted!"
      script {
        if (env.IS_ROLLING) {
          emailext(
            subject: "Build aborted: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Build aborted! ${env.BUILD_URL}",
            recipientProviders: [contributor(), developers(), requestor()],
            attachLog: true,
            compressLog: true,
            replyTo: env.RELEASE_EMAIL,
            saveOutput: false
          )
        } else if (env.IS_RELEASE) {
          emailext(
            subject: "Build aborted: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Build aborted! ${env.BUILD_URL}",
            recipientProviders: [previous()],
            attachLog: true,
            compressLog: true,
            replyTo: env.RELEASE_EMAIL,
            saveOutput: false
          )
        } else if (env.IS_PR || env.IS_DEV) {
          emailext(
            subject: "Build aborted: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Build aborted! ${env.BUILD_URL}",
            recipientProviders: [requestor()],
            attachLog: true,
            compressLog: true,
            replyTo: env.DEV_EMAIL,
            saveOutput: false
          )
        } else {
          echo "Unknown build type"
        }
      }
    }

    fixed {
      script {
        if (env.IS_ROLLING) {
          emailext(
            subject: "Resolved failing pipeline: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Resolved failing pipeline! ${env.BUILD_URL}",
            recipientProviders: [requestor()],
            attachLog: false,
            replyTo: env.RELEASE_EMAIL,
            saveOutput: false
          )
        } else if (env.IS_RELEASE) {
          emailext(
            subject: "Resolved failing pipeline: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Resolved failing pipeline! ${env.BUILD_URL}",
            recipientProviders: [previous()],
            attachLog: false,
            replyTo: env.RELEASE_EMAIL,
            saveOutput: false
          )
        } else if (env.IS_PR || env.IS_DEV) {
          emailext(
            subject: "Resolved failing pipeline: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Resolved failing pipeline! ${env.BUILD_URL}",
            recipientProviders: [requestor()],
            attachLog: false,
            replyTo: env.DEV_EMAIL,
            saveOutput: false
          )
        } else {
          echo "Unknown build type"
        }
      }
    }

    failure {
      script {
        if (env.IS_ROLLING) {
          emailext(
            subject: "Failed: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Failed! ${env.BUILD_URL}",
            recipientProviders: [requestor()],
            attachLog: true,
            compressLog: true,
            replyTo: env.RELEASE_EMAIL,
            saveOutput: false
          )
        } else if (env.IS_RELEASE) {
          emailext(
            subject: "Failed: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Failed! ${env.BUILD_URL}",
            recipientProviders: [previous()],
            attachLog: true,
            compressLog: true,
            replyTo: env.RELEASE_EMAIL,
            saveOutput: false
          )
        } else if (env.IS_PR || env.IS_DEV) {
          emailext(
            subject: "Failed: ${env.JOB_NAME} ${env.BUILD_NUMBER}",
            body: "Failed! ${env.BUILD_URL}",
            recipientProviders: [requestor()],
            attachLog: true,
            compressLog: true,
            replyTo: env.DEV_EMAIL,
            saveOutput: false
          )
        } else {
          echo "Unknown build type"
        }
      }
    }

    cleanup {
      echo "Cleaning up!"
      sh 'podman logout --all'
      sh 'podman image rm ${REGISTRY}/${PROJECT}/${IMAGE}:${TAG} || true'
    }

  }
}
// vim: ft=groovy
