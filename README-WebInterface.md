# Azure Resource Inventory (ARI) Web Interface

A simple, containerized web interface for the Azure Resource Inventory PowerShell module that can be deployed to Azure Container Instances.

## 🌟 Overview

This project provides a modern, user-friendly web interface for the Azure Resource Inventory (ARI) PowerShell module. Instead of running PowerShell commands manually, users can access a beautiful web interface to generate comprehensive Excel reports of their Azure environments.

### Key Features

- **🌐 Web-Based Interface**: Modern, responsive web UI built with Bootstrap 5
- **🐳 Containerized**: Runs in Docker containers for consistent deployment
- **☁️ Azure-Ready**: Designed for deployment to Azure Container Instances
- **📊 Real-Time Progress**: Live progress updates and log streaming
- **📁 File Downloads**: Direct download of generated Excel and diagram files
- **🔐 Secure**: Supports Azure service principal authentication
- **⚡ Fast**: Optimized container with pre-installed dependencies

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Web Browser   │───▶│  Node.js Server  │───▶│ PowerShell ARI  │
│   (Frontend)    │    │   (Backend API)  │    │     Module      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌──────────────────┐
                       │  Azure Resources │
                       │   (Inventory)    │
                       └──────────────────┘
```

## 📋 Prerequisites

### For Local Development
- Docker Desktop
- Node.js 18+ (for local development)
- PowerShell 7+ (for local development)

### For Azure Deployment
- Azure CLI
- Azure subscription with appropriate permissions
- Docker (for building images)

## 🚀 Quick Start

### Option 1: Deploy to Azure (Recommended)

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd <repository-name>
   ```

2. **Login to Azure**:
   ```bash
   az login
   ```

3. **Run the deployment script**:
   ```bash
   cd azure-deployment
   ./deploy.sh
   ```

4. **Access your application**:
   The script will output the application URL when deployment completes.

### Option 2: Run Locally with Docker

1. **Build the Docker image**:
   ```bash
   docker build -t ari-web-interface .
   ```

2. **Run the container**:
   ```bash
   docker run -p 3000:3000 ari-web-interface
   ```

3. **Access the application**:
   Open your browser to `http://localhost:3000`

### Option 3: Local Development

1. **Install dependencies**:
   ```bash
   cd web
   npm install
   ```

2. **Install PowerShell modules** (requires PowerShell 7+):
   ```powershell
   Install-Module -Name AzureResourceInventory -Force
   Install-Module -Name ImportExcel -Force
   Install-Module -Name Az.Accounts -Force
   Install-Module -Name Az.ResourceGraph -Force
   # ... other required modules
   ```

3. **Start the development server**:
   ```bash
   npm run dev
   ```

## 🔧 Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Port for the web server | `3000` |
| `NODE_ENV` | Node.js environment | `production` |

### Azure Authentication

The web interface supports multiple authentication methods:

1. **Service Principal** (Recommended for production):
   - Application ID
   - Secret
   - Tenant ID

2. **Device Login** (Interactive):
   - Requires user interaction
   - Not suitable for automated scenarios

## 📖 Usage Guide

### 1. Access the Web Interface

Navigate to your deployed application URL or `http://localhost:3000` for local development.

### 2. Fill in the Form

**Required Fields:**
- **Tenant ID**: Your Azure tenant ID

**Optional Fields:**
- **Subscription ID**: Leave empty to inventory all subscriptions
- **Application ID & Secret**: For service principal authentication
- **Report Name**: Custom name for the generated report
- **Azure Environment**: Choose your Azure cloud environment

**Options:**
- **Include Resource Tags**: Include tags in the inventory
- **Security Center Data**: Include Azure Security Center information
- **Skip Network Diagram**: Skip network topology generation
- **Skip Azure Advisor**: Skip advisor recommendations
- **Lite Mode**: Generate reports without charts
- **Debug Mode**: Enable detailed logging

### 3. Generate the Report

Click "Generate Azure Resource Inventory" and monitor the progress in real-time.

### 4. Download Results

Once complete, download the generated Excel files and network diagrams.

## 📁 Project Structure

```
.
├── web/                          # Web application
│   ├── index.html               # Frontend interface
│   ├── server.js                # Backend API server
│   └── package.json             # Node.js dependencies
├── azure-deployment/            # Azure deployment files
│   ├── deploy-aci.json         # ARM template
│   ├── deploy-aci.bicep        # Bicep template
│   └── deploy.sh               # Deployment script
├── Dockerfile                   # Container configuration
├── README-WebInterface.md       # This documentation
└── [ARI Module Files]          # Original ARI PowerShell module
```

## 🐳 Docker Container Details

The container includes:
- **Ubuntu 22.04** base image
- **PowerShell 7.4+** runtime
- **Node.js 18+** for the web server
- **Azure PowerShell modules** pre-installed
- **ARI module** from source
- **Web application** with all dependencies

### Container Specifications
- **CPU**: 2 cores (configurable)
- **Memory**: 4GB (configurable)
- **Storage**: Ephemeral (reports stored in `/tmp/reports`)
- **Port**: 3000

## 🔒 Security Considerations

### Authentication
- Use Azure service principals for production deployments
- Store secrets securely (Azure Key Vault recommended)
- Rotate credentials regularly

### Network Security
- Deploy in private networks when possible
- Use Azure Application Gateway for SSL termination
- Implement IP restrictions if needed

### Data Protection
- Reports are stored temporarily in container storage
- Consider implementing persistent storage for report retention
- Ensure compliance with data retention policies

## 🚨 Troubleshooting

### Common Issues

1. **Container fails to start**:
   ```bash
   # Check container logs
   az container logs --resource-group <rg-name> --name <container-name>
   ```

2. **PowerShell module errors**:
   ```bash
   # Verify modules are installed
   docker exec -it <container-id> pwsh -Command "Get-Module -ListAvailable"
   ```

3. **Authentication failures**:
   - Verify tenant ID, application ID, and secret
   - Check Azure AD permissions
   - Ensure service principal has appropriate RBAC roles

4. **Memory issues**:
   - Increase container memory allocation
   - Use the "Lite" mode option
   - Process smaller subscriptions separately

### Debug Mode

Enable debug mode in the web interface for detailed logging:
- Check browser developer console
- Monitor server logs
- Review PowerShell execution output

## 📊 Performance Optimization

### For Large Environments
- Use **Lite Mode** to skip chart generation
- Skip network diagrams for faster execution
- Process subscriptions individually
- Increase container resources (CPU/Memory)

### Container Optimization
- Pre-built images with cached modules
- Optimized PowerShell module loading
- Efficient file handling and cleanup

## 🔄 Updates and Maintenance

### Updating the ARI Module
1. Update the source ARI module files
2. Rebuild the Docker image
3. Redeploy to Azure Container Instances

### Monitoring
- Use Azure Monitor for container health
- Set up alerts for failures
- Monitor resource utilization

## 💰 Cost Considerations

### Azure Container Instances Pricing
- **CPU**: ~$0.0012 per vCPU per second
- **Memory**: ~$0.00016 per GB per second
- **Networking**: Standard rates apply

### Cost Optimization Tips
- Use smaller container sizes when possible
- Stop containers when not in use
- Consider Azure Container Apps for auto-scaling

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project follows the same license as the original Azure Resource Inventory module.

## 🆘 Support

For issues related to:
- **Web Interface**: Create an issue in this repository
- **ARI Module**: Refer to the original ARI documentation
- **Azure Services**: Contact Azure Support

## 🔗 Related Links

- [Azure Resource Inventory (Original)](https://github.com/microsoft/ARI)
- [Azure Container Instances Documentation](https://docs.microsoft.com/en-us/azure/container-instances/)
- [PowerShell in Docker](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux)
- [Azure CLI Reference](https://docs.microsoft.com/en-us/cli/azure/)

---

**Happy Inventorying! 🎉**