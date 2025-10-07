FROM mcr.microsoft.com/powershell:lts-ubuntu-22.04

# Install system deps, Python, and Azure CLI
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      python3 python3-pip ca-certificates curl gnupg lsb-release software-properties-common jq && \
    # Install Azure CLI
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash && \
    rm -rf /var/lib/apt/lists/*

# Install Python deps
COPY requirements-web.txt /tmp/requirements-web.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements-web.txt

# Prepare app directory
WORKDIR /app
COPY app /app/app
COPY test-auth.ps1 /app/test-auth.ps1

# ===== TESTING MODE: Copy local modified modules instead of using PowerShell Gallery =====
# Copy our locally modified AzureResourceInventory module
COPY Modules /usr/local/share/powershell/Modules/AzureResourceInventory/3.6.11/modules
COPY *.ps* /usr/local/share/powershell/Modules/AzureResourceInventory/3.6.11/
# ===== END TESTING MODE =====

# Preinstall Az modules and ARI at build time for faster startup
RUN pwsh -NoProfile -Command \
    "Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted; \
     Install-Module -Name Az.Accounts -Force -AcceptLicense -Scope AllUsers; \
     Install-Module -Name Az.Resources -Force -AcceptLicense -Scope AllUsers; \
     Install-Module -Name Az.Storage -Force -AcceptLicense -Scope AllUsers"
     
# Note: Removed AzureResourceInventory from Install-Module since we're using local copy

# Default output directory inside container
ENV ARI_OUTPUT_DIR=/data/AzureResourceInventory
RUN mkdir -p /data/AzureResourceInventory
VOLUME ["/data"]

ENV PYTHONUNBUFFERED=1 PORT=8000

EXPOSE 8000

CMD ["python3", "-m", "app.main"]

