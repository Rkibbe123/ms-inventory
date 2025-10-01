# Manual Container Update Instructions for v4.7 Nuclear Bypass
# Run these commands in the Container Apps console or via az containerapp exec

# 1. Connect to the container
az containerapp exec --name azure-resource-inventory --resource-group rg-rkibbe-2470

# 2. Once inside the container, backup the current main.py
cp /app/app/main.py /app/app/main.py.backup

# 3. Edit the main.py file (you can copy-paste the new content)
# The key changes are in the generate_force_device_login_script function
# Look for line ~427 and replace the entire function with the nuclear version

# 4. Add the new CLI device login route
# This should be added after the force_device_login route

# 5. Restart the Flask application (if needed)
# The container should auto-restart Flask when files change

# Key Nuclear Bypass Features Added:
# - Complete environment variable clearing including all AZURE_*, MSI_*, ARM_*, IDENTITY_*, IMDS_* variables
# - Module removal and re-import to clear cached authentication
# - HTTP-level IMDS blocking by modifying /etc/hosts
# - Multiple fallback authentication methods
# - New Azure CLI alternative route at /cli-device-login

# Alternative: Create new image manually
# If you have access to a machine with Docker connectivity:
# 1. Copy the updated main.py to a machine with Docker
# 2. Build: docker build -t rkazureinventory.azurecr.io/azure-resource-inventory:v4.7 .
# 3. Push: docker push rkazureinventory.azurecr.io/azure-resource-inventory:v4.7
# 4. Update container app to use v4.7 image