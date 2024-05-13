#!/bin/bash
ACR_REGISTRY=""
RESOURCE_GROUP=""
LOCATION=""
CSSC_COMMAND=""
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="../deployment.log"
while [[ $# -gt 0 ]]; do
	key="$1"
	case $key in
		-r)
			ACR_REGISTRY="$2"
			;;
		-g)
			RESOURCE_GROUP="$2"
			;;
		-wf)
			CSSC_COMMAND="$2"
			;;
		acr) 
			;;
		*)
			echo "Invalid input format."
			exit 1
			;;
	esac
	shift 2
done

function create_continuous_patching_workflow(){
  echo "Creating continuous patching workflow..." 
  local bicep_file_name="CSSC-AutoImagePatching.bicep"
  local deploymentName="continuouspatchingdeployment"
  echo_separator
  
  minutesHoursUtcCron=$(date -u -v +120S "+%M %H")
  cronExpression="$minutesHoursUtcCron * * *"
  cd ACR-CSSC
  
  # Deploy using az deployment group create command
  echo "Deploying supply chain security workflow tasks for registry $ACR_REGISTRY..."
  az deployment group create --name "$deploymentName" \
						   --resource-group "$RESOURCE_GROUP" \
						   --template-file "$bicep_file_name" \
						   --parameters "AcrName=$ACR_REGISTRY" "AcrLocation=$LOCATION" >> "$LOG_FILE" 2>&1
  if [ $? -eq 0 ]; then
	  echo "SUCCESS: Continuous patching workflow has been set up successfully. Exit code: $?" >> "$LOG_FILE" 2>&1
	  echo "SUCCESS: Deployment successful. Check '$LOG_FILE' for details."
  else
	  echo "FAILURE: Continuous patching workflow set up failed. Exit code: $?" >> "$LOG_FILE" 2>&1
	  echo "FAILURE: Deployment failed. Check '$LOG_FILE' for error messages."
  fi

  echo_separator
  echo "Setting up schedule for continuous patching.."  
  
  az acr task timer update \
  	--name CSSC-ScanRegistryAndSchedulePatch \
	--registry $ACR_REGISTRY \
	--timer-name daily \
	--schedule "$cronExpression" \
	--enabled true \
	--output json >> "$LOG_FILE" 2>&1

  if [ $? -ne 0 ]; then
  	  echo "ERROR: Setting up schedule for continuous patching failed. Exit code: $?" >> "$LOG_FILE" 2>&1
	  echo "ERROR: Error while setting up schedule for continuous patching. Check '$LOG_FILE' for details."
  fi
  
  az acr task update --name CSSC-ScanRegistryAndSchedulePatch -r $ACR_REGISTRY --status Enabled --output json >> "$LOG_FILE" 2>&1

  if [ $? -ne 0 ]; then
	  echo "ERROR: Error while enabling schedule for continuous patch. Exit code: $?" >> "$LOG_FILE" 2>&1
	  echo "ERROR: Error while enabling schedule for continuous patch. Check '$LOG_FILE' for error messages."
  fi
}

function download_required_artifacts(){
  echo "Downloading required artifacts..."
  local git_repo_url="https://github.com/siby-george/ACR-CSSC.git"
  local acrfolder="ACR-CSSC"
  local bicep_file_name="CSSC.bicep"
  if [ -f "$acrfolder/$bicep_file_name" ]; then
	  echo "File '$bicep_file_name' already cached on your local drive."
  else
	  echo "Downloading artifacts from git repository..."
	  git clone -b Cssc-workflow $git_repo_url
	  # Change to the artifacts directory
  fi
}

function create_acr_vulnerability_workflow(){
  echo "Creating ACR vulnerability scan workflow..."
  echo ""
  echo "az acr cssc-workflow
	   --name vulnerabilityscan
	   --type scan-v1
	   --registry $ACR_REGISTRY"
  echo ""
  echo_separator

  request_body='{
	  "location": "'"$LOCATION"'",
	  "identity": {
		"type": "SystemAssigned"
	  },
	  "properties": {
		"status": "Enabled",
		"platform": {
		  "os": "linux",
		  "architecture": "amd64"
		},
		"agentConfiguration": {
		  "cpu": 2
		},
		"timeout": 3600,
		"step": {
		  "type": "EncodedTask",
		  "encodedTaskContent": "dmVyc2lvbjogdjEuMS4wCsOvwrvCv3ZlcnNpb246IHYxLjEuMApzdGVwczoKICAjIFRhc2sxLiBQZXJmb3JtIHRoZSB2dWxuZXJhYmlsaXR5IHNjYW4gZm9yIHRoZSBpbnB1dCBpbWFnZQogIC0gY21kOiB8CiAgICAgIGNhY2hlMTYgaW1hZ2UgXAogICAgICB7ey5SdW4uUmVnaXN0cnl9fS97ey5SdW4uUmVwb3NpdG9yeX19Ont7LlJ1bi5HaXRUYWd9fSBcCiAgICAgIC0tZm9ybWF0IHNhcmlmIFwKICAgICAgLS1vdXRwdXQgLi97ey5WYWx1ZXMuUmVwb3NpdG9yeX19X3Z1bG5lcmFiaWxpdHlzY2FuLnNhcmlmCiAgLSBjbWQ6IHwKICAgICAgY2FjaGUxNyBhdHRhY2ggXAogICAgICAtLWFydGlmYWN0LXR5cGUgYXBwbGljYXRpb24vc2FyaWYranNvbiBcCiAgICAgIHt7LlJ1bi5SZWdpc3RyeX19L3t7LlJ1bi5SZXBvc2l0b3J5fX06e3suUnVuLkdpdFRhZ319IFwKICAgICAgLi97ey5WYWx1ZXMuUmVwb3NpdG9yeX19X3Z1bG5lcmFiaWxpdHlzY2FuLnNhcmlm",
		  "values": []
		},
		"trigger": {
		  "baseImageTrigger": null,
		  "artifactPushTrigger": {
							"filters": {
								"onReferrer": false,
								"repositoryNames": [],
								"tagNamesRegex": "^(?!.*-patched$).*$"
							},
							"name": "ArtifactPushTriggerForReferrer3"
						}
		},
		"credentials": {},
		"isSystemTask": false
	  }
  }'
  
  az resource create -g $RESOURCE_GROUP --api-version "2024-03-01-preview" --name "vulnerabilityscan" --id "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_REGISTRY/tasks/vulnerabilityscan" --is-full-object --properties "$request_body" --output json >> "$LOG_FILE" 2>&1
  if [ $? -ne 0 ]; then
	  echo "Error while setting cssc-workflow scan. Check '$LOG_FILE' for error messages."
  fi
}

function create_acr_copacetic_workflow(){
  echo "Creating ACR copacetic workflow..."
  echo_separator
  echo "az acr cssc-workflow
	   --name acrcopatask
	   --type copa-patch-v1
	   --registry $ACR_REGISTRY
	   --parameters patch-tag-format='{{.Repository}}:{{.Tag}}-patched"
  
  echo ""
  echo_separator

  request_body='{
	"location": "'"$LOCATION"'",
	"identity": {
	  "type": "SystemAssigned"
	},
	"properties": {
	  "status": "Enabled",
	  "platform": {
		"os": "linux",
		"architecture": "amd64"
	  },
	  "agentConfiguration": {
		"cpu": 2
	  },
	  "timeout": 3600,
	  "step": {
		"type": "EncodedTask",
		"encodedTaskContent": "dmVyc2lvbjogdjEuMS4wCsOvwrvCv3ZlcnNpb246IHYxLjEuMAphbGlhczoKICB2YWx1ZXM6CiAgICBwYXRjaGltYWdldGFzazogQ1NTQy1QYXRjaEltYWdlCnN0ZXBzOgogIC0gaWQ6IHByaW50LWlucHV0cwogICAgY21kOiB8CiAgICAgICAgYmFzaCAtYyAnZWNobyAiU2NhbmluZyBpbWFnZSBmb3IgdnVsbmVyYWJpbGl0eSBhbmQgcGF0Y2gge3suUnVuLlJlcG9zaXRvcnl9fTp7ey5SdW4uR2l0VGFnfX0iJwogIC0gaWQ6IHNldHVwLWRhdGEtZGlyCiAgICBjbWQ6IGJhc2ggbWtkaXIgLi9kYXRhCgogIC0gaWQ6IGdlbmVyYXRlLXRyaXZ5LXJlcG9ydAogICAgY21kOiB8CiAgICAgIGdoY3IuaW8vYXF1YXNlY3VyaXR5L3RyaXZ5IGltYWdlIFwKICAgICAge3suUnVuLlJlZ2lzdHJ5fX0ve3suUnVuLlJlcG9zaXRvcnl9fTp7ey5SdW4uR2l0VGFnfX0gXAogICAgICAtLXZ1bG4tdHlwZSBvcyBcCiAgICAgIC0taWdub3JlLXVuZml4ZWQgXAogICAgICAtLWZvcm1hdCBqc29uIFwKICAgICAgLS1vdXRwdXQgL3dvcmtzcGFjZS9kYXRhL3Z1bG5lcmFiaWxpdHktcmVwb3J0X3RyaXZ5X3t7bm93IHwgZGF0ZSAiMjAyMy0wMS0wMiJ9fS5qc29uCiAgLSBjbWQ6IG1jci5taWNyb3NvZnQuY29tL2F6dXJlLWNsaSBiYXNoIC1jICdqcSAiLlJlc3VsdHNbXS5WdWxuZXJhYmlsaXRpZXMgfCBsZW5ndGgiIC93b3Jrc3BhY2UvZGF0YS92dWxuZXJhYmlsaXR5LXJlcG9ydF90cml2eV97e25vdyB8IGRhdGUgIjIwMjMtMDEtMDIifX0uanNvbiA+IC93b3Jrc3BhY2UvZGF0YS92dWxDb3VudC50eHQnCiAgLSBjbWQ6IGJhc2ggZWNobyAiJChjYXQgL3dvcmtzcGFjZS9kYXRhL3Z1bENvdW50LnR4dCkiCiAgLSBpZDogbGlzdC1vdXRwdXQtZmlsZQogICAgY21kOiBiYXNoIGxzIC1sIC93b3Jrc3BhY2UvZGF0YQogIC0gY21kOiBheiBjbG91ZCByZWdpc3RlciAtbiBkb2dmb29kIC0tZW5kcG9pbnQtYWN0aXZlLWRpcmVjdG9yeSBodHRwczovL2xvZ2luLndpbmRvd3MtcHBlLm5ldCAtLWVuZHBvaW50LWFjdGl2ZS1kaXJlY3RvcnktZ3JhcGgtcmVzb3VyY2UtaWQgaHR0cHM6Ly9ncmFwaC5wcGUud2luZG93cy5uZXQvIC0tZW5kcG9pbnQtYWN0aXZlLWRpcmVjdG9yeS1yZXNvdXJjZS1pZCBodHRwczovL21hbmFnZW1lbnQuY29yZS53aW5kb3dzLm5ldC8gLS1lbmRwb2ludC1nYWxsZXJ5IGh0dHBzOi8vY3VycmVudC5nYWxsZXJ5LmF6dXJlLXRlc3QubmV0LyAtLWVuZHBvaW50LW1hbmFnZW1lbnQgaHR0cHM6Ly9tYW5hZ2VtZW50LmNvcmUud2luZG93cy5uZXQvIC0tZW5kcG9pbnQtcmVzb3VyY2UtbWFuYWdlciBodHRwczovL2FwaS1kb2dmb29kLnJlc291cmNlcy53aW5kb3dzLWludC5uZXQvIC0tc3VmZml4LXN0b3JhZ2UtZW5kcG9pbnQgY29yZS50ZXN0LWNpbnQuYXp1cmUtdGVzdC5uZXQgLS1zdWZmaXgta2V5dmF1bHQtZG5zIC52YXVsdC1pbnQuYXp1cmUtaW50Lm5ldCAtLXN1ZmZpeC1hY3ItbG9naW4tc2VydmVyLWVuZHBvaW50IC5henVyZWNyLXRlc3QuaW8gLS1lbmRwb2ludC1zcWwtbWFuYWdlbWVudCAiaHR0cHM6Ly9tYW5hZ2VtZW50LmNvcmUud2luZG93cy5uZXQ6ODQ0My8iCiAgLSBjbWQ6IGF6IGNsb3VkIHNldCAtbiBkb2dmb29kCiAgLSBjbWQ6IGF6IGxvZ2luIC0taWRlbnRpdHkKICAtIGNtZDogYXogYWNyIHJlcG9zaXRvcnkgc2hvdy10YWdzIC1uICRSZWdpc3RyeU5hbWUgLS1yZXBvc2l0b3J5IHt7LlJ1bi5SZXBvc2l0b3J5fX0KICAtIGlkOiBldmFsLWV4ZWN1dGUtcGF0Y2gKICAgIGNtZDogfAogICAgICBtY3IubWljcm9zb2Z0LmNvbS9henVyZS1jbGkgYmFzaCAtYyAndnVsQ291bnQ9JChjYXQgL3dvcmtzcGFjZS9kYXRhL3Z1bENvdW50LnR4dCkgJiYgXAogICAgICBbICR2dWxDb3VudCAtZ3QgMCBdICYmIFwKICAgICAgYXogYWNyIHRhc2sgcnVuIC0tbmFtZSAkcGF0Y2hpbWFnZXRhc2sgLS1yZWdpc3RyeSAkUmVnaXN0cnlOYW1lIC0tc2V0IFNPVVJDRV9SRVBPU0lUT1JZPXt7LlJ1bi5SZXBvc2l0b3J5fX0gLS1zZXQgU09VUkNFX0lNQUdFX1RBRz17ey5SdW4uR2l0VGFnfX0gLS1kZWJ1ZyAtLW5vLXdhaXQgXAogICAgICB8fCBlY2hvICJObyB2dWxuZXJhYmlsaXR5IGluIHRoZSBpbWFnZSB7ey5SdW4uUmVwb3NpdG9yeX19Ont7LlJ1bi5HaXRUYWd9fSIn",
		"values": []
	  },
	  "trigger": {
		"baseImageTrigger": {
		  "baseImageTriggerType": "Runtime",
		  "updateTriggerPayloadType": "Default",
		  "status": "Enabled",
		  "name": "defaultBaseimageTriggerName"
		},
		"artifactPushTrigger": {
						  "filters": {
							  "onReferrer": false,
							  "repositoryNames": [],
							  "tagNamesRegex": "^(?!.*-patched$).*$"
						  },
						  "name": "ArtifactPushTriggerForReferrer2"
					  }
	  },
	  "credentials": {},
	  "isSystemTask": false
	}
  }';
  
  acrcopaceticpresponse=$(az resource create -g $RESOURCE_GROUP --api-version "2024-03-01-preview" --name "acrcopatask" --id "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_REGISTRY/tasks/acrcopatask" --is-full-object --properties "$request_body")
  
  parsedPrincipalId=$(echo "$acrcopaceticpresponse" | jq -r '.identity.principalId')
  resourceId=$(echo "$acrcopaceticpresponse" | jq -r '.id')
  
  request_body_permission='{
	  "roleDefinitionId": "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c",
	  "principalId": "'"$parsedPrincipalId"'",
	  "principalType": "ServicePrincipal"
  }'

  contributorRoleId="b24988ac-6180-42a0-ab88-20f7382dd24c"
  generated_uuid=$(uuidgen)
  acrpermissionresponse=$(az resource create -g $RESOURCE_GROUP --api-version "2022-04-01" --name "$generated_uuid" --id "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_REGISTRY/providers/Microsoft.Authorization/roleAssignments/$generated_uuid" --properties "$request_body_permission" --output json >> "$LOG_FILE" 2>&1)
  if [ $? -ne 0 ]; then
	  echo "Error while setting cssc-workflow copa. Check '$LOG_FILE' for error messages."
  fi
}

function clean_registry_artifacts(){
	#az role assignment list --scope "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_REGISTRY" --role Contributor

	az resource delete -g $RESOURCE_GROUP --id "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_REGISTRY/tasks/CSSC-PatchImage" --api-version 2019-04-01
	az resource delete -g $RESOURCE_GROUP --id "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_REGISTRY/tasks/CSSC-ScanImageAndSchedulePatch" --api-version 2019-04-01
	az resource delete -g $RESOURCE_GROUP --id "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_REGISTRY/tasks/CSSC-ScanRepoAndSchedulePatch"  --api-version 2019-04-01
	az resource delete -g $RESOURCE_GROUP --id "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_REGISTRY/tasks/CSSC-ScanRegistryAndSchedulePatch" --api-version 2019-04-01
	az resource delete -g $RESOURCE_GROUP --id "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_REGISTRY/providers/Microsoft.Authorization/roleAssignments/50220559-5db7-50bb-9956-41f1630dd837" --api-version 2020-04-01-preview
	az resource delete -g $RESOURCE_GROUP --id "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_REGISTRY/providers/Microsoft.Authorization/roleAssignments/8f321f77-0d4c-5c8d-bfcc-727a9817d5d0" --api-version 2020-04-01-preview
	az resource delete -g $RESOURCE_GROUP --id "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_REGISTRY/providers/Microsoft.Authorization/roleAssignments/ad056d1a-af2b-531b-b0e9-98b32b854e6d" --api-version 2020-04-01-preview
	az resource delete -g $RESOURCE_GROUP --id "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_REGISTRY/tasks/acrcopatask" --api-version 2019-04-01
	az resource delete -g $RESOURCE_GROUP --id "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_REGISTRY/tasks/vulnerabilityscan" --api-version 2019-04-01
	az resource delete -g $RESOURCE_GROUP --id "/subscriptions/b4e7b127-622b-4b84-aab3-a1d0ca5b381d/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_REGISTRY/providers/Microsoft.Authorization/roleAssignments/ad056d1a-af2b-531b-b0e9-98b32b854e6d" --api-version 2020-04-01-preview
}

function call_acquisition_csscworkflow(){
  create_acr_copacetic_workflow 
  create_acr_vulnerability_workflow
}

function call_entire_csscworkflow(){
  create_continuous_patching_workflow
  call_acquisition_csscworkflow
}

function validate_global_parameters(){
	SCRIPT_FILE_NAME=$(basename "$0")	
	if [ -z "$ACR_REGISTRY" ] || [ -z "$RESOURCE_GROUP" ] || [ -z "$CSSC_COMMAND" ]; then
		echo "Usage: " 
		echo
		echo "  " $SCRIPT_FILE_NAME "-r <registryname> -g <resourcegroup> -cssc <csscworkflowcommand>"
		echo ""
	fi
	if [[ "$CSSC_COMMAND" != "patch" && "$CSSC_COMMAND" != "scan"  && "$CSSC_COMMAND" != "continuouspatch" && "$CSSC_COMMAND" != "all" && "$CSSC_COMMAND" != "track-progress" && "$CSSC_COMMAND" != "clean" ]]; then
		echo "Invalid value for -cssc <WORKFLOWCOMMAND> parameter. Please provide valid value."
		echo ""
		echo "Available commands for <csscworkflowcommand>:  "
		echo "  patch: 		set up patching tasks for acquisition workflow"
		echo "  scan:  		set up vulnerability scan tasks for acquisition workflow"
		echo "  continuouspatch:  	set up continuous patching for existing repositories"
		echo "  all: 		        set up complete workflow (patch + scan + continuous patching)"
		echo "  track-progress: 	track existing cssc-workflow runs"
		echo ""
		exit 1
	fi
}

function track_cssc_workflow(){
  local statusFilter="Succeeded"
  echo "Tracking cssc workflow..."
  echo_separator
  echo "az acr cssc-workflow track-progress
	   --name csscdemoworkflow
	   --type patch
	   --filter-status $statusFilter"
  echo
  echo_separator

  az acr task list-runs --registry $ACR_REGISTRY --name acrcopatask --resource-group $RESOURCE_GROUP --run-status $statusFilter -o table

  filteredRuns="az acr task list-runs --registry $ACR_REGISTRY --name acrcopatask --resource-group $RESOURCE_GROUP --run-status $statusFilter -o json"
  runId=$($filteredRuns | jq .[0].runId -r)
  
  echo "View logs for the runId: $runId"
  echo_separator
  echo "az acr cssc-workflow track-progress
	   --name csscdemoworkflow
	   --type patch
	   --show-logs --run-id $runId" 
  echo ""
  echo_separator

  az acr task logs --registry $ACR_REGISTRY --name acrcopatask --resource-group $RESOURCE_GROUP --run-id $runId
}

function initialize_cssc_workflow(){
  echo "Getting location of the registry"
  acr_info="az acr show --name $ACR_REGISTRY" 
  LOCATION=$($acr_info | jq -r '.location')
}

echo_separator() {
	echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

validate_global_parameters
download_required_artifacts
initialize_cssc_workflow

case $CSSC_COMMAND in
	patch) create_acr_copacetic_workflow ;;
	scan) create_acr_vulnerability_workflow ;;
	continuouspatch) create_continuous_patching_workflow ;;
	all) call_entire_csscworkflow ;;
	track-progress) track_cssc_workflow ;;
	clean) clean_registry_artifacts ;;
	*) echo "Invalid cssc command. Available options -patch | -scan | -continuouspatch | -all" ;;
esac