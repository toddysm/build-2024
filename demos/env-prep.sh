# 1. Copy a vulnerable Python image to the repository in Docker Hub
skopeo copy -a docker://docker.io/library/python:3.12.2 docker://docker.io/payalmahesh/python:3.12

# 2. Signin to Azure Preview Portal
https://aka.ms/acr/portal/preview