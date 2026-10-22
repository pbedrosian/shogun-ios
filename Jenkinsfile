// Optional executor for the same validation used by GitHub Actions.
// Configure a trusted macOS agent with full Xcode, Python 3, and an iOS runtime.
pipeline {
    agent { label 'macos && xcode' }
    options {
        timeout(time: 35, unit: 'MINUTES')
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
        buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
    }
    parameters {
        booleanParam(name: 'RUN_SONAR', defaultValue: false, description: 'Run SonarQube Cloud on trusted dev/main branch builds only')
        string(name: 'SONAR_PROJECT_KEY', defaultValue: '', description: 'Existing SonarQube Cloud project key')
        string(name: 'SONAR_ORGANIZATION', defaultValue: '', description: 'Existing SonarQube Cloud organization key')
    }
    stages {
        stage('Checkout') {
            steps {
                deleteDir()
                checkout scm
                // Full history is required for useful Sonar new-code attribution.
                sh 'if [ "$(git rev-parse --is-shallow-repository)" = true ]; then git fetch --unshallow; fi'
            }
        }
        stage('Build, analyze, test and coverage') {
            steps { sh 'python3 scripts/ci/run.py' }
        }
        stage('SonarQube Cloud') {
            when {
                expression { params.RUN_SONAR && !env.CHANGE_ID && env.BRANCH_NAME in ['dev', 'main'] }
            }
            steps {
                withEnv(["SONAR_PROJECT_KEY=${params.SONAR_PROJECT_KEY}", "SONAR_ORGANIZATION=${params.SONAR_ORGANIZATION}", 'SONAR_HOST_URL=https://sonarcloud.io']) {
                    withCredentials([string(credentialsId: 'shogun-sonar-token', variable: 'SONAR_TOKEN')]) {
                        sh '''
                            set +x
                            test -n "$SONAR_PROJECT_KEY" || { echo 'SONAR_PROJECT_KEY is required'; exit 1; }
                            test -n "$SONAR_ORGANIZATION" || { echo 'SONAR_ORGANIZATION is required'; exit 1; }
                            command -v sonar-scanner >/dev/null || { echo 'Install the official SonarScanner CLI on this agent'; exit 1; }
                            sonar-scanner "-Dsonar.projectKey=$SONAR_PROJECT_KEY" "-Dsonar.organization=$SONAR_ORGANIZATION"
                        '''
                    }
                }
            }
        }
    }
    post {
        always {
            junit testResults: 'build/ci/junit.xml', allowEmptyResults: true
            archiveArtifacts artifacts: 'build/ci/*.log,build/ci/*.json,build/ci/*.xml,build/ci/summary.md,build/ci/Tests.xcresult/**', allowEmptyArchive: true
        }
    }
}
