# 🚀 Azure Resource Inventory Web Interface - Deployment Guide

This guide walks you through deploying the ARI Web Interface to Azure Container Instances step by step.

## 📋 Prerequisites Checklist

Before starting, ensure you have:

- [ ] Azure CLI installed and configured
- [ ] Docker Desktop installed and running
- [ ] An Azure subscription with appropriate permissions
- [ ] PowerShell 7+ (for local testing)

## 🎯 Deployment Options

### Option 1: Automated Deployment (Recommended)

The easiest way to deploy is using our automated script:

```bash
# 1. Clone the repository
git clone <your-repo-url>
cd <repo-directory>

# 2. Login to Azure
az login

# 3. Run the deployment script
cd azure-deployment
./deploy.sh
```

**What the script does:**
1. Creates a resource group
2. Creates an Azure Container Registry
3. Builds and pushes the Docker image
4. Deploys to Azure Container Instances
5. Provides the application URL

### Option 2: Manual Deployment

If you prefer manual control:

#### Step 1: Create Azure Resources

```bash
# Set variables
RESOURCE_GROUP="rg-ari-web"
LOCATION="eastus"
ACR_NAME="acrariwebXXXX"  # Replace XXXX with unique suffix
CONTAINER_GROUP="ari-web-interface"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create container registry
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --admin-enabled true
```

#### Step 2: Build and Push Image

```bash
# Get ACR login server
ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer --output tsv)

# Build image
docker build -t ari-web-interface:latest .

# Tag for ACR
docker tag ari-web-interface:latest $ACR_LOGIN_SERVER/ari-web-interface:latest

# Login to ACR and push
az acr login --name $ACR_NAME
docker push $ACR_LOGIN_SERVER/ari-web-interface:latest
```

#### Step 3: Deploy Container Instance

```bash
# Get ACR credentials
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query username --output tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query passwords[0].value --output tsv)

# Deploy using ARM template
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file azure-deployment/deploy-aci.json \
    --parameters \
        containerGroupName=$CONTAINER_GROUP \
        containerImageName="$ACR_LOGIN_SERVER/ari-web-interface:latest" \
        registryUsername=$ACR_USERNAME \
        registryPassword=$ACR_PASSWORD
```

## 🔧 Configuration Options

### Container Resources

Adjust based on your needs:

| Workload Size | CPU Cores | Memory (GB) | Estimated Cost/Month* |
|---------------|-----------|-------------|----------------------|
| Small (1-5 subscriptions) | 1 | 2 | ~$30 |
| Medium (5-20 subscriptions) | 2 | 4 | ~$60 |
| Large (20+ subscriptions) | 4 | 8 | ~$120 |

*Estimated costs for East US region, running 8 hours/day

### Environment Variables

You can customize the deployment with these parameters:

```bash
# In deploy-aci.json parameters
{
    "containerGroupName": "your-container-name",
    "cpuCores": "2",
    "memoryInGb": "4",
    "dnsNameLabel": "your-unique-dns-name"
}
```

## 🔐 Security Setup

### Service Principal Authentication (Recommended)

1. **Create a service principal:**
   ```bash
   az ad sp create-for-rbac --name "ari-web-sp" --role "Reader" --scopes "/subscriptions/<subscription-id>"
   ```

2. **Note the output:**
   ```json
   {
     "appId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
     "displayName": "ari-web-sp",
     "password": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
     "tenant": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
   }
   ```

3. **Use these credentials in the web interface**

### Required Azure Permissions

The service principal needs these permissions:
- **Reader** role on subscriptions to inventory
- **Security Reader** role (if using Security Center features)

## 🧪 Testing Your Deployment

### 1. Health Check

```bash
# Get the application URL
APP_URL=$(az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name "deploy-aci" \
    --query properties.outputs.applicationUrl.value \
    --output tsv)

# Test health endpoint
curl $APP_URL/api/health
```

### 2. Environment Check

```bash
# Check PowerShell modules
curl $APP_URL/api/check-environment
```

### 3. Full Test

1. Open the application URL in your browser
2. Fill in the form with test credentials
3. Generate a small inventory (single subscription)
4. Verify file download works

## 📊 Monitoring and Logs

### View Container Logs

```bash
az container logs --resource-group $RESOURCE_GROUP --name $CONTAINER_GROUP
```

### Monitor Container Status

```bash
az container show --resource-group $RESOURCE_GROUP --name $CONTAINER_GROUP --output table
```

### Set Up Alerts

```bash
# Create action group for notifications
az monitor action-group create \
    --resource-group $RESOURCE_GROUP \
    --name "ari-alerts" \
    --short-name "ari-alerts" \
    --email-receivers name="admin" email="admin@company.com"

# Create alert rule for container failures
az monitor metrics alert create \
    --resource-group $RESOURCE_GROUP \
    --name "ari-container-down" \
    --scopes "/subscriptions/<sub-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerInstance/containerGroups/$CONTAINER_GROUP" \
    --condition "count static < 1" \
    --description "ARI container is down" \
    --evaluation-frequency 5m \
    --window-size 5m \
    --severity 2 \
    --action-groups "/subscriptions/<sub-id>/resourceGroups/$RESOURCE_GROUP/providers/microsoft.insights/actionGroups/ari-alerts"
```

## 🔄 Updates and Maintenance

### Updating the Application

1. **Update the code**
2. **Rebuild and push the image:**
   ```bash
   docker build -t ari-web-interface:latest .
   docker tag ari-web-interface:latest $ACR_LOGIN_SERVER/ari-web-interface:latest
   docker push $ACR_LOGIN_SERVER/ari-web-interface:latest
   ```

3. **Restart the container:**
   ```bash
   az container restart --resource-group $RESOURCE_GROUP --name $CONTAINER_GROUP
   ```

### Scaling Options

For high availability, consider:
- **Azure Container Apps** for auto-scaling
- **Azure Kubernetes Service** for complex scenarios
- **Load balancer** for multiple instances

## 🚨 Troubleshooting

### Common Issues and Solutions

| Issue | Symptoms | Solution |
|-------|----------|----------|
| Container won't start | Status shows "Failed" | Check logs with `az container logs` |
| Authentication errors | 401/403 errors in logs | Verify service principal permissions |
| Out of memory | Container restarts frequently | Increase memory allocation |
| Slow performance | Long execution times | Increase CPU cores or use Lite mode |
| Network issues | Can't reach Azure APIs | Check network security groups |

### Debug Commands

```bash
# Container status
az container show --resource-group $RESOURCE_GROUP --name $CONTAINER_GROUP

# Container logs
az container logs --resource-group $RESOURCE_GROUP --name $CONTAINER_GROUP

# Container events
az container show --resource-group $RESOURCE_GROUP --name $CONTAINER_GROUP --query instanceView.events

# Execute commands in container
az container exec --resource-group $RESOURCE_GROUP --name $CONTAINER_GROUP --exec-command "/bin/bash"
```

## 💰 Cost Management

### Cost Optimization Tips

1. **Stop when not in use:**
   ```bash
   az container stop --resource-group $RESOURCE_GROUP --name $CONTAINER_GROUP
   az container start --resource-group $RESOURCE_GROUP --name $CONTAINER_GROUP
   ```

2. **Use smaller instances for testing:**
   - 1 CPU core, 1GB RAM for development
   - Scale up for production workloads

3. **Monitor usage:**
   ```bash
   az consumption usage list --start-date 2024-01-01 --end-date 2024-01-31
   ```

### Cleanup Resources

When you're done:

```bash
# Delete everything
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

## 📞 Getting Help

### Support Channels

1. **Application Issues**: Check the logs and troubleshooting guide
2. **Azure Issues**: Contact Azure Support
3. **ARI Module Issues**: Refer to the original ARI documentation

### Useful Commands Reference

```bash
# Quick status check
az container show --resource-group $RESOURCE_GROUP --name $CONTAINER_GROUP --query "{Status:instanceView.state,IP:ipAddress.ip,FQDN:ipAddress.fqdn}" --output table

# Get application URL
az deployment group show --resource-group $RESOURCE_GROUP --name "deploy-aci" --query properties.outputs.applicationUrl.value --output tsv

# Restart container
az container restart --resource-group $RESOURCE_GROUP --name $CONTAINER_GROUP

# View real-time logs
az container logs --resource-group $RESOURCE_GROUP --name $CONTAINER_GROUP --follow
```

---

🎉 **Congratulations!** You now have a fully functional Azure Resource Inventory web interface running in the cloud!