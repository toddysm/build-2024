# Prerequisites:
az login
az acr login -n acrbuild2024.azurecr.io   

# Demo Steps
# 1. Create a new patch workflow
./src/create-patch-workflow.sh -r acrbuild2024 -g rg-build-2024 -wf continuouspatch

# 2. Pull and scan the patched image
docker pull acrbuild2024.azurecr.io/python:3.12-patched
trivy image --ignore-unfixed --vuln-type os acrbuild2024.azurecr.io/python:3.12-patched | grep Total

# 3. Pull and scan the original image
docker pull acrbuild2024.azurecr.io/python:3.12
trivy image --ignore-unfixed --vuln-type os acrbuild2024.azurecr.io/python:3.12 | grep Total