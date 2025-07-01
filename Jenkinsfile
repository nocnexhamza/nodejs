pipeline {
  agent {
    kubernetes {
      yaml '''
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins: agent
spec:
  securityContext:
    runAsUser: 0
  dnsPolicy: None
  dnsConfig:
    nameservers:
      - 8.8.8.8
      - 1.1.1.1
  containers:
    - name: jnlp
      image: nocnex/jenkins-agent:nerdctlv4
      args: ['$(JENKINS_SECRET)', '$(JENKINS_NAME)']
      tty: true
      securityContext:
        privileged: true
      volumeMounts:
        - name: workspace-volume
          mountPath: /home/jenkins/agent
        - name: buildkit-cache
          mountPath: /tmp/buildkit-cache
    - name: node
      image: node:18-slim
      command: ['cat']
      tty: true
      volumeMounts:
        - name: workspace-volume
          mountPath: /home/jenkins/agent
  volumes:
    - name: workspace-volume
      emptyDir: {}
    - name: buildkit-cache
      emptyDir: {}
'''
    }
  }

  environment {
    // Updated to use "nocnex/nodejs"
    DOCKER_IMAGE = "nocnex/nodejs"
    REGISTRY = "docker.io"
    KUBE_NAMESPACE = "default"
  }

  stages {
    stage('Checkout Code') {
      steps {
        container('node') {
          git url: 'https://github.com/nocnexhamza/nodejs.git', branch: 'main'
        }
      }
    }

    stage('Install & Test') {
      steps {
        container('node') {
          sh 'npm install --package-lock-only || true'
          sh 'npm ci --only=production'
          sh 'npm test || true'
        }
      }
    }

    stage('Build & Push Image') {
      steps {
        container('jnlp') {
          withCredentials([usernamePassword(
            credentialsId: 'dockerhublogin',
            usernameVariable: 'DOCKER_USER',
            passwordVariable: 'DOCKER_PASS'
          )]) {
            sh '''
              # Debug information
              echo "Building image: ${REGISTRY}/${DOCKER_IMAGE}:${BUILD_NUMBER}"
              echo "Using Docker Hub username: $DOCKER_USER"
              
              # Configure BuildKit
              mkdir -p /etc/buildkit
              cat <<EOF > /etc/buildkit/buildkitd.toml
[worker.containerd]
  namespace = "buildkit"
  snapshotter = "overlayfs"

[registry."docker.io"]
  insecure = false
EOF

              # Start BuildKit daemon
              buildkitd --config /etc/buildkit/buildkitd.toml &
              sleep 5

              # Manual Docker Hub login test
              echo "Testing Docker Hub credentials..."
              docker login -u $DOCKER_USER -p $DOCKER_PASS docker.io
              
              # Create repository if needed
              echo "Creating repository if needed..."
              curl -u "$DOCKER_USER:$DOCKER_PASS" -X POST \
                "https://hub.docker.com/v2/repositories/${DOCKER_IMAGE}/" \
                -H "Content-Type: application/json" \
                -d '{"is_private": false}' || echo "Repository creation may have failed or already exists"
              
              # Wait to ensure repository is ready
              sleep 3

              # Build and push image
              buildctl build \
                --frontend dockerfile.v0 \
                --local context=. \
                --local dockerfile=. \
                --output type=image,name=docker.io/${DOCKER_IMAGE}:${BUILD_NUMBER},push=true \
                --export-cache type=local,dest=/tmp/buildkit-cache \
                --import-cache type=local,src=/tmp/buildkit-cache \
                --opt registry.username=${DOCKER_USER} \
                --opt registry.password=${DOCKER_PASS}
            '''
          }
        }
      }
    }

    stage('Deploy to Kubernetes') {
      steps {
        container('jnlp') {
          withCredentials([kubeconfigFile(
            credentialsId: 'subarentest',
            variable: 'KUBECONFIG'
          )]) {
            sh '''
              kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nodejs-app
  namespace: ${KUBE_NAMESPACE}
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nodejs
  template:
    metadata:
      labels:
        app: nodejs
    spec:
      containers:
      - name: nodejs-app
        image: docker.io/${DOCKER_IMAGE}:${BUILD_NUMBER}
        ports:
        - containerPort: 3000
        resources:
          limits:
            memory: "512Mi"
            cpu: "500m"
          requests:
            memory: "256Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: nodejs-service
  namespace: ${KUBE_NAMESPACE}
spec:
  selector:
    app: nodejs
  ports:
    - protocol: TCP
      port: 80
      targetPort: 3000
  type: LoadBalancer
EOF

              kubectl rollout status deployment/nodejs-app -n ${KUBE_NAMESPACE} --timeout=120s
            '''
          }
        }
      }
    }
  }

  post {
    always {
      container('jnlp') {
        sh 'rm -rf /tmp/buildkit-cache/*'
      }
    }
    success {
      container('jnlp') {
        withCredentials([kubeconfigFile(credentialsId: 'subarentest', variable: 'KUBECONFIG')]) {
          sh '''
            echo "Deployment successful!"
            kubectl get svc nodejs-service -n ${KUBE_NAMESPACE}
          '''
        }
      }
    }
    failure {
      container('jnlp') {
        withCredentials([kubeconfigFile(credentialsId: 'subarentest', variable: 'KUBECONFIG')]) {
          sh '''
            echo "Deployment failed. Checking logs:"
            kubectl describe deployment/nodejs-app -n ${KUBE_NAMESPACE}
            kubectl logs -l app=nodejs -n ${KUBE_NAMESPACE} --tail=50
            echo "BuildKit logs:"
            buildkitd --debug 2>&1 | tail -n 50
          '''
        }
      }
    }
  }
}
