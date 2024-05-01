> [!IMPORTANT]  
> **Step 1** : Pre requisite (Docker need to installed to test setup locally)

Objective:

<aside>
💡 Build a Dockerfile for deploying a simple Ruby on Rails application with PostgreSQL DB‬ enabled. Application and DB should run on different containers.‬
  
</aside>

‭ **Solve as:**

Initially fork repo in your github personal a/c.
Example 3 repo url: https://github.com/evans22j/Budget-App.git

—> after that clone it locally, next

**First** create an **.env** file req for config/db.yml as:

```bash
DB_HOST=db
DB_USER=Budgy
DB_PASSWORD=Budgy
DB_NAME=budgy_development
```

After that update config/db.yml as:

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  # For details on connection pooling, see Rails configuration guide
  # https://guides.rubyonrails.org/configuring.html#database-pooling
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  host: <%= ENV.fetch('DB_HOST', 'localhost') %>
  database: <%= ENV['DB_NAME'] %>
  username: <%= ENV['DB_USER'] %>
  password: <%= ENV['DB_PASSWORD'] %>
```

next, create a Dockerfile to dockerise RubyOnRails Budget-App

Dockerfile as:

```docker
# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.1.2
FROM registry.docker.com/library/ruby:$RUBY_VERSION as base

# Install Node.js dependencies
RUN apt-get update && apt-get install -y nodejs postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

# Rails app lives here
WORKDIR /rails

# Set development environment
ENV RAILS_ENV="development" \
    BUNDLE_WITHOUT=""

# Install application gems
COPY Gemfile* Gemfile.lock ./
RUN gem install bundler:2.3.6
RUN bundle install
RUN bundle exec rails db:create db:migrate
RUN rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["bundle", "exec", "rails", "s", "-p" "3000", "-b", "0.0.0.0"]
```

next create a docker-compose.yml file as :

```yaml
version: "3.8"
services:
  db:
    image: postgres:14.1
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=Budgy
      - POSTGRES_PASSWORD=Budgy
      - POSTGRES_DB=budgy_development

  web:
    build: .
    # image: surajwaghmare35/budget-app-web
    command: >
      sh -c "rm -f tmp/pids/server.pid &&
            rails db:create db:migrate &&
            bundle exec rails s -p 3000 -b '0.0.0.0'"
    ports:
      - "3000:3000"
    volumes:
      - .:/rails
    depends_on:
      - db
    env_file:
      - .env # Specify the path to your .env file

volumes:
  pgdata:
```

Now lets, test step 1 by execute in root of your project: (optional)

```bash
docker compose up --build -d
```

after that on browser access webapp as: http://127.0.0.1:3000

> [!IMPORTANT]  
> **Step 2:** Pre requisite,

<aside>
💡 To test k8s setup locally make sure you have k8s development cluster running, u can setup using minikube/k3d or kind. (I have setup using Minikube.)
  
</aside>

Objective:
sudo sysctl fs.protected_regular=0
Build a YAML file for the same application you’ve used in your first step to deploy it on‬ K8s cluster.

Deploy PostgreSQL as StatefulSet, setup ingess for webapp.

**Solve as :**

create required manifest in manifests dir as:

mkdir -pv manifests

vim manifests/**budget-app-web.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: budget-app-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: budget-app-web
  template:
    metadata:
      labels:
        app: budget-app-web
    spec:
      containers:
        - name: budget-app-web
          image: surajwaghmare35/budget-app-web
          command: ["/bin/sh"]
          args:
            [
              "-c",
              "rm -f tmp/pids/server.pid && rails db:create db:migrate && bundle exec rails s -p 3000 -b '0.0.0.0'",
            ]
          resources:
            # limits:
            # memory: "128Mi"
            # cpu: "500m"
          ports:
            - containerPort: 3000
          env:
            - name: DB_HOST
              value: "postgres-service"
            - name: DB_USER
              value: "Budgy"
            - name: DB_PASSWORD
              value: "Budgy"
            - name: DB_NAME
              value: "budgy_development"
---
apiVersion: v1
kind: Service
metadata:
  name: budget-app-web-service
spec:
  selector:
    app: budget-app-web
  ports:
    - port: 3000 # Use a specific port for NodePort
      targetPort: 3000
      protocol: TCP
      # nodePort: 30000
  type: NodePort
```

vim manifests/postgre-db-sts.yaml

```yaml
# headless-pg-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  labels:
    app: postgres-a
spec:
  selector:
    app: postgres-a
  ports:
    - port: 5432
      # targetPort: 5432
      # protocol: TCP
  clusterIP: None

---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-sts
spec:
  selector:
    matchLabels:
      app: postgres-a # has to match .spec.template.metadata.labels
  serviceName: "postgres-service"
  replicas: 1 # by default is 1
  minReadySeconds: 10 # by default is 0
  template:
    metadata:
      labels:
        app: postgres-a # has to match .spec.selector.matchLabels
    spec:
      terminationGracePeriodSeconds: 10
      containers:
        - name: postgres
          image: postgres:14.1
          env:
            - name: POSTGRES_DB
              value: budgy_development
            - name: POSTGRES_USER
              value: Budgy
            - name: POSTGRES_PASSWORD
              value: Budgy
          ports:
            - containerPort: 5432
          volumeMounts:
            - name: pgdata
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
    - metadata:
        name: pgdata
      spec:
        accessModes: ["ReadWriteOnce"]
        # storageClassName: "my-storage-class" //standard
        # storageClassName: "standard"
        resources:
          requests:
            storage: 1Gi
```

vim manifests/postgres-pv.yaml

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pgdata
spec:
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Recycle
  storageClassName: default
  hostPath:
    path: /tmp/pgdata
    # hard-coded local path
    type: DirectoryOrCreate
```

vim manifests/ingress.yaml

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: budget-app-web-ingress
  labels:
    name: ingress-lb
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$1

spec:
  # ingressClassName: nginx
  rules:
    - host: budget-app.example.com # Replace with your actual hostname
        paths:
          - pathType: Prefix
            path: "/"
            backend:
              service:
                name: budget-app-web-service
                port:
                  # number: 80
                  number: 3000
```

after that update your mainHost **/etc/hosts** file by adding entry as: minikube-ip [budget-app.example.com](http://budget-app.example.com/)

> Lets enable minikube ingress addon

```bash
minikube addons enable ingress
minikube addons list | grep enabled
```

```bash
# Here the docker image build locally in step 1, we need to push it in dockerHub registry as:
# You can push a new image to repository using the CLI:

# login to docker-hub, then
docker tag local-image:tagname new-repo:tagname
docker push new-repo:tagname
```

we can test k8s setup as: (optional)

```bash
kubectl apply -f manifests
watch -x kubectl get no,sc,pv,pvc,svc,deploy,po,ing,hpa,sts,cm,secrets -A

# check pgsql pod status
kubectl logs pods/postgres-sts-0 -f

# once all pod up, execute & open url in browser
minikube service budget-app-web-service --url
# or
kubectl port-forward svc/budget-app-web-service --address 0.0.0.0 3000:3000
```

> [!IMPORTANT]  
> Step 3 : Objective

<aside>
💡 Deploy ArgoCD to manage the deployment of application‬ using GitOps in private GitHub repository.

The expected ArgoCD config files include application.yaml , ArgoCD config maps (argocd-cm and argocd-rbac-cm), a config file for the k8s manifest files.‬

</aside>

**Solve as:**

Install argocd

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f argocd/argo-install.yaml
watch -x kubectl get pods -n argocd

# argocd default username is : admin
# get argocd inital-admin-pass as:
kubectl get secrets -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d;echo
```

Next create an argocd : argocd-repo-cred.yaml.yaml

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-private-https-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/Surajwaghmare35/Budget-App-Rb
  password: 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
  username: surajwaghmare35
  insecure: "true" # Ignore validity of server's TLS certificate. Defaults to "false"
  forceHttpBasicAuth: "true" # Skip auth method negotiation and force usage of HTTP basic auth. Defaults to "false"
  enableLfs: "true" # Enable git-lfs for this repository. Defaults to "false"
```

```bash
# it will create prive git repo secret in argcd
kubectl apply -n argocd -f argocd/argocd-repo-cred.yaml
```

After that create an argocd : application.yaml for manual sync

(Note: we can setup same using UI also )

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: budget-app-argocd
spec:
  destination:
    name: ""
    namespace: default
    server: "https://kubernetes.default.svc"
  source:
    path: manifests
    repoURL: "https://github.com/Surajwaghmare35/Budget-App-Rb"
    targetRevision: HEAD
  sources: []
  project: default
  syncPolicy:
    automated: null
```

Download argocd cli to setup private repo credential

```bash
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# execute, & check in argocd-ui under "Settings/Repositories"
# argocd repo add https://github.com/argoproj/argocd-example-apps --username <username> --password <password>
# note: in above replace github repo as per yours
```

after that execute & configure github-https auth manually:

```bash
# it will create an application in argcd ui
kubectl apply -n argocd -f argocd/application.yaml

# Now execute
kubectl port-forward -n argocd svc/argocd-server --address 0.0.0.0 8080:443
```

To log-in to argocd-server, on browser type: [127.0.0.1:8080](http://127.0.0.1:8080/)

<aside>
💡 we will see an argocd-app is created,

Now, Click 0n ApplicationName: **budget-app-argocd**

then, **sync —> synchronise.**

(by following above steps will deploy pod it k8s cluster)

</aside>

> [!IMPORTANT]  
> Step 4: objective

<aside>
  
💡 S‭et up Tekton pipelines and the Tekton dashboard.

The pipeline should download the‬ source code from the public fork of the sample project (Which you’ve containerized in‬ the first step),

build the image, and push it to Docker Hub using kaniko.

( Note: ‭manually run the pipeline from the Tekton dashboard.‬)

</aside>

**Solve as:**

<aside>
💡 Follow reference doc : [https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)

</aside>

1st create a secret for **docker-hub** access

```bash
# This command creates a Secret of type [kubernetes.io/dockerconfigjson]
kubectl create secret docker-registry docker-credentials \
  --docker-email=surajwaghmare35@gmail.com \
  --docker-username=surajwaghmrare35 \
  --docker-password=dckr_pat_D3luHLSh2WSXmDbkez90WAg5w6E \
  --docker-server=https://index.docker.io/v1/

```

**alternative,**

If you already ran docker login, you can copy that credential into k8s cluster as:

```bash
kubectl create secret generic docker-credentials \
    --from-file=.dockerconfigjson=$HOME/.docker/config.json \
    --type=kubernetes.io/dockerconfigjson

    #--dry-run=client -o yaml > k8s-docker-secret.yaml

```

To, retrieve the .data.dockerconfigjson field from that new Secret and decode the data:

```bash
kubectl get secret <secret-name> -o jsonpath='{.data.*}' | base64 -d;echo
# OR
kubectl get secret <secret-name> -o jsonpath='{.data.*}' | base64 -d | jq .

```

<aside>
💡 Follow reference doc: [https://tekton.dev/docs/how-to-guides/kaniko-build-push](https://tekton.dev/docs/how-to-guides/kaniko-build-push/)

</aside>

Install tekton pipeline

```bash
kubectl apply -f tekton/tekton-release.yaml
# Install Tekton Dashboard
kubectl apply -f tekton/tekton-dashboard.yaml
watch -x kubectl get pods -n tekton-pipeline

# apply tekton rbac
kubectl apply -f tekton/tekton-rbac.yaml
kubectl get clusterrolebindings,clusterroles,rolebindings,roles -A | grep -inF tekton
```

create tekton **pipeline.yaml**

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: clone-build-push
spec:
  description: |
    This pipeline clones a git repo, builds a Docker image with Kaniko and
    pushes it to a registry
  params:
    - name: repo-url
      type: string
    - name: image-reference
      type: string
  workspaces:
    - name: shared-data
    - name: docker-credentials
  tasks:
    - name: fetch-source
      taskRef:
        name: git-clone
      workspaces:
        - name: output
          workspace: shared-data
      params:
        - name: url
          value: $(params.repo-url)
    - name: build-push
      runAfter: ["fetch-source"]
      taskRef:
        name: kaniko
      workspaces:
        - name: source
          workspace: shared-data
        - name: dockerconfig
          workspace: docker-credentials
      params:
        - name: IMAGE
          value: $(params.image-reference)
```

create tekton **pipelinerun.yaml**

```yaml
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: clone-build-push-run-
  # Name: clone-build-push-run
spec:
  pipelineRef:
    name: clone-build-push
  podTemplate:
    securityContext:
      fsGroup: 65532
  workspaces:
    - name: shared-data
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi
    - name: docker-credentials
      secret:
        secretName: docker-credentials
        items:
          - key: .dockerconfigjson
            path: config.json
  params:
    - name: repo-url
      value: https://github.com/Surajwaghmare35/Budget-App-Rb.git
    - name: image-reference
      # value: container.registry.com/sublocation/my_app:version
      value: docker.io/surajwaghmare35/budget-app-web:latest
```

<aside>
💡 Install tekton-cli as .deb package

</aside>

You are ready to install the Tasks and run the pipeline.

```bash
# Install the git-clone and kaniko Tasks:
tkn hub install task git-clone
tkn hub install task kaniko
tkn task list

# Apply the Secret with your Docker credentials
kubectl apply -f tekton/k8s-docker-secret.yaml

# Apply the Pipeline
kubectl apply -f tekton/pipeline.yaml
# Create the PipelineRun:
kubectl create -f tekton/pipelinerun.yaml

# see pipelinerun logs
tkn pipelinerun logs  clone-build-push-run-4kgjr -f
```

**Access Tekton Dashboard**

```bash
kubectl port-forward -n tekton-pipelines svc/tekton-dashboard 9097:9097
```

You can now open the Dashboard in your browser at [http://127.0.0.1:9097](http://127.0.0.1:9097/)

if works well all, you will see complete steps as:

[k8s-argocd-tekton-kaniko1.webm](https://github.com/Surajwaghmare35/Budget-App-Rb/assets/68895144/75e8c59e-49e5-4284-a4c9-c3635c67d5dc)

# Done
