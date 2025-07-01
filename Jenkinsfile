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
    runAsUser: 1000
    fsGroup: 1000
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
      volumeMounts:
        - name: workspace-volume
          mountPath: /home/jenkins/agent
        - name: buildkit-cache
          mountPath: /tmp/buildkit-cache
        - name: kube-config
          mountPath: /home/jenkins/.kube
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
      volumeMounts:
        - name: kube-config
          mountPath: /home/jenkins/.kube
  volumes:
    - name: workspace-volume
      emptyDir: {}
    - name: buildkit-cache
      emptyDir: {}
    - name: kube-config
      emptyDir: {}
'''
    }
  }

  environment {
    DOCKER_IMAGE = "nocnex/nodejs-app-v2"
    REGISTRY = "docker.io"
    KUBE_NAMESPACE = "default"
    KUBECONFIG = "/home/jenkins/.kube/config"
    BUILDKIT_CONFIG_DIR = "/tmp/buildkit-config"
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
            )
          ]) {
            sh '''
              echo "Building image: ${REGISTRY}/${DOCKER_IMAGE}:${BUILD_NUMBER}"
              
              # Configure BuildKit in user-writable directory
              mkdir -p ${BUILDKIT_CONFIG_DIR}
              cat <<EOF > ${BUILDKIT_CONFIG_DIR}/buildkitd.toml
[worker.containerd]
  namespace = "buildkit"
  snapshotter = "overlayfs"

[registry."docker.io"]
  insecure = false
EOF

              buildkitd --config ${BUILDKIT_CONFIG_DIR}/buildkitd.toml &
              sleep 5

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
            variable: 'KUBECONFIG_FILE'
          )]) {
            sh '''
              # Ensure .kube directory exists and has correct permissions
              mkdir -p /home/jenkins/.kube
              cp "${KUBECONFIG_FILE}" "${KUBECONFIG}"
              chmod 600 "${KUBECONFIG}"

              echo "Applying deployment..."
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
      app: nodejs-app
  template:
    metadata:
      labels:
        app: nodejs-app
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
    app: nodejs-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 3000
  type: LoadBalancer
EOF

              echo "Waiting for deployment rollout..."
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
        sh 'rm -rf ${BUILDKIT_CONFIG_DIR}'
      }
    }
    success {
      container('kubectl') {
        withCredentials([file(
          credentialsId: 'kubernetes_file',
          variable: 'KUBECONFIG_FILE'
        )]) {
          sh '''
            echo "=== Deployment Successful ==="
            kubectl get deployments,svc,pods -n ${KUBE_NAMESPACE}
          '''
        }
      }
    }
    failure {
      container('kubectl') {
        withCredentials([file(
          credentialsId: 'kubernetes_file',
          variable: 'KUBECONFIG_FILE'
        )]) {
          sh '''
            echo "=== Cluster Status ==="
            kubectl get all -n ${KUBE_NAMESPACE} || true
            
            echo "=== Deployment Description ==="
            kubectl describe deployment/nodejs-app -n ${KUBE_NAMESPACE} || true
            
            echo "=== Pod Logs ==="
            kubectl logs -l app=nodejs-app -n ${KUBE_NAMESPACE} --tail=50 || true
            
            echo "=== Recent Events ==="
            kubectl get events -n ${KUBE_NAMESPACE} --sort-by='.lastTimestamp' | tail -n 20 || true
          '''
        }
      }
    }
  }
}
