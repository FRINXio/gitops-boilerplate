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
  "\t just deploy \n" + \
  "\t just --set values \"local-values.yaml\" deploy \n" + \
  "\t just --set exclude \"frinx-machine-monitoring,frinx-machine\" deploy" \
  }}\n'

  @just --list

[private]
create-namespace:
  kubectl create namespace {{namespace}} || true

[private]
deploy-stage-operators values="":
  #!/usr/bin/env bash
  set -euo pipefail
  VALUES={{values}}

  pushd {{justfileDir}}/apps/{{operatorChartName}} > /dev/null
    helm dependency update
    helm upgrade --install --create-namespace -n {{namespace}} {{operatorChartName}} . --values values.yaml $(for val in {{values}}; do if [ -f $val ]; then echo --values $val; fi ; done)
  popd > /dev/null

[private]
uninstall-stage-operators values="":
  #!/usr/bin/env bash
  set -euo pipefail
  pushd {{justfileDir}}/apps/{{operatorChartName}} > /dev/null
    helm dependency update
    helm template -n {{namespace}} {{operatorChartName}} . ---values values.yaml $(for val in {{values}}; do if [ -f $val ]; then echo --values $val; fi ; done) | kubectl delete -f- || true
  popd > /dev/null


# Function to deploy a stage with the ability to exclude apps and specify values files
[private]
deploy-stage exclude values:
  #!/usr/bin/env bash
  set -euo pipefail
  SKIP_CHARTS={{exclude}}
  IFS=',' read -r -a EXCLUDE <<< "{{operatorChartName}},${SKIP_CHARTS}"

  pushd {{justfileDir}}/apps  > /dev/null
  APPS=($(ls -d */ | sed 's:/*$::'))

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
        helm upgrade --install --create-namespace -n {{namespace}} $(basename $PWD) . --values values.yaml $(for val in {{values}}; do if [ -f $val ]; then echo --values $val; fi ; done)

      popd > /dev/null
    fi
  done
  popd  > /dev/null

# Function to deploy a stage with the ability to exclude apps and specify values files
[private]
uninstall-stage exclude:
  #!/usr/bin/env bash
  set -euo pipefail

  SKIP_CHARTS={{exclude}}
  IFS=',' read -r -a EXCLUDE <<< "{{operatorChartName}},${SKIP_CHARTS}"

  pushd {{justfileDir}}/apps  > /dev/null
  APPS=($(ls -d */ | sed 's:/*$::'))

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
        helm uninstall -n {{namespace}} $(basename $PWD) || true

      popd > /dev/null
    fi
  done
  popd  > /dev/null

# Recipe to deploy apps with optional apps exclusion and values files
deploy:
  just create-namespace
  just docker-secret
  just deploy-stage-operators {{values}}
  just deploy-stage "{{exclude}}" "{{values}}"

# Recipe to uninstall apps with optional apps exclusion and values files
uninstall:
  just uninstall-stage "{{exclude}}" 
  just uninstall-stage-operators "{{values}}"

# Recipe to start minikube with max CPUs and 24G memory, instess addon enabled
minikube-start:
  minikube start --cpus=max --memory=24G --addons=ingress

# Create docker secret from $HOME/.docker/config.json
docker-secret:
  kubectl create secret generic regcred \
    --from-file=.dockerconfigjson=$HOME/.docker/config.json \
    --type=kubernetes.io/dockerconfigjson \
    --namespace={{namespace}} || true
