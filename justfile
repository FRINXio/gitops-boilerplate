# Define environment variables (if any)
set dotenv-load := true

# Global ENVs
justfileDir   := justfile_directory()
namespace   := shell('basename $1', justfileDir)
operatorChartName := "frinx-machine-operators"

# Execution ENVs. Can be overided on startup
values := "local-values.yaml"
include := ""
context := 'true'

[private]
default:
  @echo '{{ \
  "\nJustfile for Frinx Machine execution: start Frinx Machine stage locally\n\n" + \
  "Default env variables: \n\n" + \
  "\tvalues: Add extra value files to helm command\n" + \
  "\tinclude: Include apps to installation process\n\n" + \
  "Example of usage: \n\n" + \
  "\t just deploy-dev \n" + \
  "\t just --set values \"local-values.yaml\" deploy-dev \n" + \
  "\t just --set include \"frinx-machine-monitoring,frinx-machine\" deploy-dev" \
  }}\n'

  @just --list

[private]
create-namespace stage:
  kubectl create namespace {{namespace}}-{{stage}} || true

[private]
uninstall-operators stage values="":
  #!/usr/bin/env bash
  set -euox pipefail
  pushd {{justfileDir}}/apps/{{stage}}/{{operatorChartName}} > /dev/null
    helm dependency update
    helm uninstall -n {{namespace}}-{{stage}} $(basename $PWD) . || true
    helm template -n {{namespace}}-{{stage}} {{operatorChartName}} . --values values.yaml $(for val in {{values}}; do if [ -f $val ]; then echo --values $val; fi ; done) | kubectl delete -f- || true
  popd > /dev/null


[private]
uninstall-crds stage values="":
  #!/usr/bin/env bash
  set -euox pipefail
  pushd {{justfileDir}}/apps/{{stage}}/{{operatorChartName}} > /dev/null
    helm dependency update
    helm template -n {{namespace}}-{{stage}} {{operatorChartName}} . --values values.yaml $(for val in {{values}}; do if [ -f $val ]; then echo --values $val; fi ; done) | kubectl delete -f- || true
  popd > /dev/null

# Function to deploy a stage with the ability to exclude apps and specify values files
[private]
deploy stage include values:
  #!/usr/bin/env bash
  set -euox pipefail

  pushd {{justfileDir}}/apps/{{stage}}

  DEPLOY_CHARTS=(./{{operatorChartName}})
  DEPLOY_CHARTS+=($(find -type d \( -name '{{operatorChartName}}' -prune \) -o -name 'Chart.yaml' -exec dirname {} \;))

  echo ${DEPLOY_CHARTS[@]}

  if [ {{include}} ]; then
    # Parse input string to array
    IFS=',' read -r -a INCLUDE <<< "{{include}}"

    # Loop through the array and build the regex filter
    FILTER=$(for val in ${INCLUDE}; do echo -regex ".*/$val/Chart.yaml -o"; done)
    
    # Remove the trailing ' -o'
    FILTER="${FILTER::-3}"

    # Construct the find command
    DEPLOY_CHARTS=($(find . -type f \( $FILTER \) -exec dirname {} \;))
  fi

  for dir in "${DEPLOY_CHARTS[@]}"; do
    if [ -d "$dir" ]; then
      pushd "$dir" > /dev/null
        BASENAME=$(basename "$PWD")

        echo "Processing directory: $BASENAME"
        helm dependency update
        helm upgrade --install --create-namespace -n {{namespace}}-{{stage}} $(basename $PWD) . --values values.yaml $(for val in {{values}}; do if [ -f $val ]; then echo --values $val; fi ; done)

      popd > /dev/null
    fi
  done

  popd  > /dev/null

# Function to deploy a stage with the ability to include apps and specify values files
[private]
uninstall stage include:
  #!/usr/bin/env bash
  set -euox pipefail

  pushd {{justfileDir}}/apps/{{stage}}

  DEPLOY_CHARTS=($(find -type d \( -name '{{operatorChartName}}' -prune \) -o -name 'Chart.yaml' -exec dirname {} \;))

  if [ {{include}} ]; then
    # Parse input string to array
    IFS=',' read -r -a INCLUDE <<< "{{include}}"

    # Loop through the array and build the regex filter
    FILTER=$(for val in ${INCLUDE}; do echo -regex ".*/$val/Chart.yaml -o"; done)
    
    # Remove the trailing ' -o'
    FILTER="${FILTER::-3}"

    # Construct the find command
    DEPLOY_CHARTS=($(find . -type f \( $FILTER \) -exec dirname {} \;))
  fi

  for dir in "${DEPLOY_CHARTS[@]}"; do
    if [ -d "$dir" ]; then
      pushd "$dir" > /dev/null
        BASENAME=$(basename "$PWD")

        echo "Processing directory: $BASENAME"
        helm uninstall -n {{namespace}}-{{stage}} $(basename $PWD) || true

      popd > /dev/null
    fi
  done
  popd  > /dev/null

# Switch kubernetes context to project related
set-context stage:
  #!/usr/bin/env bash
  set -euox pipefail
  if [ {{context}} ]; then
    kubectl config use-context kind-{{namespace}} --namespace={{namespace}}-{{stage}}
  fi

# Recipe to deploy the dev with optional apps exclusion and values files 
deploy-dev:
  just create-namespace dev
  just set-context dev
  just docker-secret dev
  just deploy dev "{{include}}" "{{values}}"

# Recipe to deploy the stage with optional apps exclusion and values files
deploy-stage:
  just create-namespace stage
  just set-context stage
  just docker-secret stage
  just deploy stage "{{include}}" "{{values}}"

# Recipe to deploy the prod with optional apps exclusion and values files
deploy-prod:
  just create-namespace prod
  just set-context prod
  just docker-secret prod
  just deploy prod "{{include}}" "{{values}}"

# Recipe to uninstall the dev stage with optional apps exclusion and values files
uninstall-dev:
  just set-context dev
  just uninstall dev "{{include}}" 
  just uninstall-operators dev "{{values}}"

# Recipe to uninstall the stage stage with optional apps exclusion and values files
uninstall-stage:
  just set-context stage
  just uninstall stage "{{include}}" 
  just uninstall-operators stage "{{values}}"

# Recipe to uninstall prod stage with optional app exclusion and values files
uninstall-prod:
  just set-context prod
  just uninstall prod "{{include}}" 
  just uninstall-operators prod "{{values}}"

remove-crds-dev:
  just set-context dev
  just uninstall-crds dev "{{values}}"

remove-crds-stage:
  just set-context stage
  just uninstall-crds stage "{{values}}"

remove-crds-prod:
  just set-context prod
  just uninstall-crds prod "{{values}}"

# Recipe to start minikube with 12 CPUs and 24G memory, instess addon enabled
cluster-start:
  kind create cluster --name {{namespace}} --config {{justfileDir}}/infra/kind/kind-config.yaml || true
  # helm upgrade --install --namespace kube-system --repo https://helm.cilium.io cilium cilium --values {{justfileDir}}/infra/kind/cilium-helm-values.yaml
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/kind/deploy.yaml
  kubectl apply -f {{justfileDir}}/infra/kind/metrics-server.yaml

# Create docker secret from $HOME/.docker/config.json
docker-secret stage:
  kubectl create secret generic regcred \
    --from-file=.dockerconfigjson=$HOME/.docker/config.json \
    --type=kubernetes.io/dockerconfigjson \
    --namespace={{namespace}}-{{stage}} || true
