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
    runAsUser: 1000  # Changed from root for security
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
        privileged: false  # Changed from true for security
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
    - name: kubectl
      image: bitnami/kubectl:latest
      command: ['cat']
      tty: true
  volumes:
    - name: workspace-volume
      emptyDir: {}
    - name: buildkit-cache
      emptyDir: {}
'''
    }
  }

  environment {
    DOCKER_IMAGE = "nocnex/nodejs-app-v2"
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
          withCredentials([
            usernamePassword(
              credentialsId: 'dockerhublogin',
              usernameVariable: 'DOCKER_USER',
              passwordVariable: 'DOCKER_PASS'
            ),
            file(
              credentialsId: 'kubernetes_file',
              variable: 'KUBECONFIG'
            )
          ]) {
            sh '''
              # Set up kubeconfig
              mkdir -p ~/.kube
              cp "$KUBECONFIG" ~/.kube/config
              chmod 600 ~/.kube/config

              # Build and push image
              echo "Building image: ${REGISTRY}/${DOCKER_IMAGE}:${BUILD_NUMBER}"
              
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

              # Build and push image
              buildctl build \\
                --frontend dockerfile.v0 \\
                --local context=. \\
                --local dockerfile=. \\
                --output type=image,name=docker.io/${DOCKER_IMAGE}:${BUILD_NUMBER},push=true \\
                --export-cache type=local,dest=/tmp/buildkit-cache \\
                --import-cache type=local,src=/tmp/buildkit-cache \\
                --opt registry.username=${DOCKER_USER} \\
                --opt registry.password=${DOCKER_PASS}
            '''
          }
        }
      }
    }

    stage('Deploy to Kubernetes') {
      steps {
        container('kubectl') {
          withCredentials([file(
            credentialsId: 'kubernetes_file',
            variable: 'KUBECONFIG'
          )]) {
            sh '''
              # Set up kubeconfig
              mkdir -p ~/.kube
              cp "$KUBECONFIG" ~/.kube/config
              chmod 600 ~/.kube/config

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
      app: nodejs-app-v2
  template:
    metadata:
      labels:
        app: nodejs-app-v2
    spec:
      containers:
      - name: nodejs-app-v2
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
    app: nodejs-app-v2
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
      container('kubectl') {
        withCredentials([file(
          credentialsId: 'kubernetes_file',
          variable: 'KUBECONFIG'
        )]) {
          sh '''
            mkdir -p ~/.kube
            cp "$KUBECONFIG" ~/.kube/config
            chmod 600 ~/.kube/config
            
            echo "Deployment successful!"
            kubectl get svc nodejs-service -n ${KUBE_NAMESPACE}
          '''
        }
      }
    }
    failure {
      container('kubectl') {
        withCredentials([file(
          credentialsId: 'kubernetes_file',
          variable: 'KUBECONFIG'
        )]) {
          sh '''
            mkdir -p ~/.kube
            cp "$KUBECONFIG" ~/.kube/config
            chmod 600 ~/.kube/config
            
            echo "Deployment failed. Checking logs:"
            kubectl describe deployment/nodejs-app -n ${KUBE_NAMESPACE}
            kubectl logs -l app=nodejs-app-v2 -n ${KUBE_NAMESPACE} --tail=50
          '''
        }
      }
    }
  }
}
