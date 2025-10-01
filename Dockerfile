# Use Ubuntu as base image for better compatibility with PowerShell and Azure modules
FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_VERSION=18.17.0
ENV POWERSHELL_VERSION=7.4.0

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    apt-transport-https \
    software-properties-common \
    ca-certificates \
    gnupg \
    lsb-release \
    unzip \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs

# Install PowerShell
RUN wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb" \
    && dpkg -i packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y powershell \
    && rm packages-microsoft-prod.deb

# Create application directory
WORKDIR /app

# Copy the entire ARI module to the container
COPY . /app/ari-source/

# Copy web application files
COPY web/ /app/web/

# Install Node.js dependencies
WORKDIR /app/web
RUN npm install --production

# Install PowerShell modules and ARI
WORKDIR /app
RUN pwsh -Command " \
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; \
    Install-Module -Name ImportExcel -Force -Scope AllUsers; \
    Install-Module -Name Az.Accounts -Force -Scope AllUsers; \
    Install-Module -Name Az.ResourceGraph -Force -Scope AllUsers; \
    Install-Module -Name Az.Storage -Force -Scope AllUsers; \
    Install-Module -Name Az.Compute -Force -Scope AllUsers; \
    Install-Module -Name Az.Resources -Force -Scope AllUsers; \
    Install-Module -Name Az.Profile -Force -Scope AllUsers; \
    Install-Module -Name Az.Advisor -Force -Scope AllUsers; \
    Install-Module -Name Az.Security -Force -Scope AllUsers; \
    Install-Module -Name Az.Monitor -Force -Scope AllUsers; \
    Install-Module -Name Az.PolicyInsights -Force -Scope AllUsers; \
    Write-Host 'PowerShell modules installed successfully'; \
    "

# Install the ARI module from source
RUN pwsh -Command " \
    \$ModulePath = '/usr/local/share/powershell/Modules/AzureResourceInventory'; \
    New-Item -ItemType Directory -Path \$ModulePath -Force; \
    Copy-Item -Path '/app/ari-source/AzureResourceInventory.psd1' -Destination \$ModulePath -Force; \
    Copy-Item -Path '/app/ari-source/AzureResourceInventory.psm1' -Destination \$ModulePath -Force; \
    Copy-Item -Path '/app/ari-source/Modules' -Destination \$ModulePath -Recurse -Force; \
    Import-Module AzureResourceInventory -Force; \
    Get-Module AzureResourceInventory; \
    Write-Host 'ARI module installed successfully'; \
    "

# Create necessary directories
RUN mkdir -p /tmp/reports /tmp/uploads

# Set permissions
RUN chmod -R 755 /app /tmp/reports /tmp/uploads

# Create a startup script
RUN echo '#!/bin/bash\n\
echo "Starting Azure Resource Inventory Web Interface..."\n\
echo "PowerShell Version: $(pwsh -Command "$PSVersionTable.PSVersion")"\n\
echo "Node.js Version: $(node --version)"\n\
echo "NPM Version: $(npm --version)"\n\
echo "Checking PowerShell modules..."\n\
pwsh -Command "Get-Module -ListAvailable | Where-Object {$_.Name -like \"Az.*\" -or $_.Name -eq \"ImportExcel\" -or $_.Name -eq \"AzureResourceInventory\"} | Select-Object Name, Version | Sort-Object Name"\n\
echo "Starting web server..."\n\
cd /app/web\n\
exec node server.js' > /app/start.sh

RUN chmod +x /app/start.sh

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3000/api/health || exit 1

# Set working directory back to web app
WORKDIR /app/web

# Start the application
CMD ["/app/start.sh"]