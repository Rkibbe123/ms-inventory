## One-page ARI Runner (Web + Container)

This adds a minimal Flask web UI that triggers the PowerShell `Invoke-ARI` command to generate Azure inventory reports. A Dockerfile is provided to run in Azure Container Apps.

### Local build and run (Docker)

```bash
docker build -t ari-runner:local .
docker run --rm -p 8000:8000 -v $(pwd)/data:/data ari-runner:local
```

Open `http://localhost:8000` and run a report. Files will appear under `./data/AzureResourceInventory`.

### Deploy to Azure Container Apps

Prereqs: Logged in with `az login` and have subscription ID.

```bash
bash deploy/aca-deploy.sh <subscription-id> <resource-group> <location> <acr-name> <app-name>
```

The script:
- Creates resource group and ACR if needed
- Builds and pushes the image with `az acr build`
- Creates or updates the Container App with external ingress on port 8000

It will output the public FQDN upon success.

### Authentication

When running in Azure Container Apps, `Invoke-ARI` will require interactive login unless you provide a service principal or enable managed identity flow. Common options:

- Use `-DeviceLogin` with `Invoke-ARI` by extending the form and app
- Use a user-assigned managed identity for the Container App and extend the PowerShell invocation to use `-Automation` and `Connect-AzAccount -Identity`

### Structure

- `app/main.py` – Flask app with UI and PowerShell invocation
- `Dockerfile` – Python + PowerShell + Az + ARI
- `deploy/aca-deploy.sh` – Azure build and deploy helper

