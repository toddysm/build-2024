# Prerequisites:
# Have Docker running
az login

# Demo Steps
# 0. Sign in to Azure Container Registry
az acr login -n acrbuild2024.azurecr.io   

# 1. Create a new patch workflow
./src/create-patch-workflow.sh -r acrbuild2024 -g rg-build-2024 -wf continuouspatch
