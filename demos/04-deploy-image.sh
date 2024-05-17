# Demo steps
# 1. Deploy the signed image
kubectl run demo-app --image-pull-policy='Always' --image=acrbuild2024.azurecr.io/flaskapp:1.0
kubectl get pods

# 2. Deploy the unsigned image

kubectl run demo-app-unsigned --image-pull-policy='Always' --image=acrbuild2024.azurecr.io/flaskapp:1.0-unsigned
kubectl get pods

# 3. Copy the signed image to GHCR
oras cp -r acrbuild2024.azurecr.io/flaskapp:1.0 ghcr.io/payalmahesh/flaskapp:1.0

# 4. Deploy image from anapproved registry
kubectl run demo-app-unapproved --image-pull-policy='Always' --image=ghcr.io/payalmahesh/flaskapp:1.0