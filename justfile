# Define environment variables (if any)
set dotenv-load := true

# Global ENVs
justfileDir   := justfile_directory()
namespace   := shell('basename $1', justfileDir)
operatorChartName := "frinx-machine-operators"

# Execution ENVs. Can be overided on startup
values := "local-values.yaml"
exclude := ""

[private]
default:
  @echo '{{ \
  "\nJustfile for Frinx Machine execution: start Frinx Machine stage locally\n\n" + \
  "Default env variables: \n\n" + \
  "\tvalues: Add extra value files to helm command\n" + \
  "\texclude: Exclude apps from installation process\n\n" + \
  "Example of usage: \n\n" + \
  "\t just deploy-dev \n" + \
  "\t just --set values \"local-values.yaml\" deploy-dev \n" + \
  "\t just --set exclude \"frinx-machine-monitoring,frinx-machine\" deploy-dev" \
  }}\n'

  @just --list

[private]
create-namespace stage:
  kubectl create namespace {{namespace}}-{{stage}} || true

[private]
deploy-operators stage values="":
  #!/usr/bin/env bash
  set -euo pipefail
  VALUES={{values}}

  pushd {{justfileDir}}/apps/{{stage}}/{{operatorChartName}} > /dev/null
    helm dependency update
    helm upgrade --install --create-namespace -n {{namespace}}-{{stage}} {{operatorChartName}} . --values values.yaml $(for val in {{values}}; do if [ -f $val ]; then echo --values $val; fi ; done)
  popd > /dev/null

[private]
uninstall-operators stage values="":
  #!/usr/bin/env bash
  set -euo pipefail
  pushd {{justfileDir}}/apps/{{stage}}/{{operatorChartName}} > /dev/null
    helm dependency update
    helm template -n {{namespace}}-{{stage}} {{operatorChartName}} . --values values.yaml $(for val in {{values}}; do if [ -f $val ]; then echo --values $val; fi ; done) | kubectl delete -f- || true
  popd > /dev/null


# Function to deploy a stage with the ability to exclude apps and specify values files
[private]
deploy stage exclude values:
  #!/usr/bin/env bash
  set -euo pipefail
  SKIP_CHARTS={{exclude}}
  IFS=',' read -r -a EXCLUDE <<< "{{operatorChartName}},${SKIP_CHARTS}"

  pushd {{justfileDir}}/apps/{{stage}}  > /dev/null
  APPS=($(find -type f -name 'Chart.yaml' -exec dirname {} \;))

  for dir in "${APPS[@]}"; do
    if [ -d "$dir" ]; then
      pushd "$dir" > /dev/null
        BASENAME=$(basename "$PWD")

        # Check if the directory name is in the ignore list
        if [[ " ${EXCLUDE[@]} " =~ " ${BASENAME} " ]]; then
          echo "Skipping directory: $BASENAME"
          popd > /dev/null
          continue
        fi

        echo "Processing directory: $BASENAME"
        helm dependency update
        helm upgrade --install --create-namespace -n {{namespace}}-{{stage}} $(basename $PWD) . --values values.yaml $(for val in {{values}}; do if [ -f $val ]; then echo --values $val; fi ; done)

      popd > /dev/null
    fi
  done
  popd  > /dev/null

# Function to deploy a stage with the ability to exclude apps and specify values files
[private]
uninstall stage exclude:
  #!/usr/bin/env bash
  set -euo pipefail

  SKIP_CHARTS={{exclude}}
  IFS=',' read -r -a EXCLUDE <<< "{{operatorChartName}},${SKIP_CHARTS}"

  pushd {{justfileDir}}/apps/{{stage}}  > /dev/null
  APPS=($(find -type f -name 'Chart.yaml' -exec dirname {} \;))

  for dir in "${APPS[@]}"; do
    if [ -d "$dir" ]; then
      pushd "$dir" > /dev/null
        BASENAME=$(basename "$PWD")

        # Check if the directory name is in the ignore list
        if [[ " ${EXCLUDE[@]} " =~ " ${BASENAME} " ]]; then
          echo "Skipping directory: $BASENAME"
          popd > /dev/null
          continue
        fi

        echo "Processing directory: $BASENAME"
        helm uninstall -n {{namespace}}-{{stage}} $(basename $PWD) || true

      popd > /dev/null
    fi
  done
  popd  > /dev/null

# Recipe to deploy the dev with optional apps exclusion and values files 
deploy-dev:
  just create-namespace dev
  just docker-secret dev
  just deploy-operators dev {{values}}
  just deploy dev "{{exclude}}" "{{values}}"

# Recipe to deploy the stage with optional apps exclusion and values files
deploy-stage:
  just create-namespace stage
  just docker-secret stage
  just deploy-operators stage {{values}}
  just deploy stage "{{exclude}}" "{{values}}"

# Recipe to deploy the prod with optional apps exclusion and values files
deploy-prod:
  just create-namespace prod
  just docker-secret prod
  just deploy-operators prod {{values}}
  just deploy prod "{{exclude}}" "{{values}}"

# Recipe to uninstall the dev stage with optional apps exclusion and values files
uninstall-dev:
  just uninstall dev "{{exclude}}" 
  just uninstall-operators dev "{{values}}"

# Recipe to uninstall the stage stage with optional apps exclusion and values files
uninstall-stage:
  just uninstall stage "{{exclude}}" 
  just uninstall-operators stage "{{values}}"

# Recipe to uninstall prod stage with optional app exclusion and values files
uninstall-prod:
  just uninstall prod "{{exclude}}" 
  just uninstall-operators prod "{{values}}"

# Recipe to start minikube with 12 CPUs and 24G memory, instess addon enabled
cluster-start:
  kind create cluster --name {{namespace}}-kind --config {{justfileDir}}/infra/kind/kind-config.yaml || true
  # helm upgrade --install --namespace kube-system --repo https://helm.cilium.io cilium cilium --values {{justfileDir}}/infra/kind/cilium-helm-values.yaml
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/kind/deploy.yaml
  kubectl apply -f {{justfileDir}}/infra/kind/metrics-server.yaml

# Create docker secret from $HOME/.docker/config.json
docker-secret stage:
  kubectl create secret generic regcred \
    --from-file=.dockerconfigjson=$HOME/.docker/config.json \
    --type=kubernetes.io/dockerconfigjson \
    --namespace={{namespace}}-{{stage}} || true
