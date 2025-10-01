# Quick Fix Instructions for Container App 500 Error

## Issue
The Force Device Login route is causing a 500 Internal Server Error in the container environment.

## Root Cause
The new `force_device_login()` function has indentation/syntax issues that work locally but fail in the container.

## Quick Fix Options

### Option 1: Disable Force Device Login Route (Immediate Fix)
1. Go to Azure Portal → Container Apps → azure-resource-inventory
2. Go to "Revision management"
3. Create new revision with older image tag
4. Use image: `rkazureinventory.azurecr.io/azure-resource-inventory:v3.0`

### Option 2: Use Manual Portal Update
Since CLI connectivity is having issues:

1. **Azure Portal** → **Resource Groups** → **rg-rkibbe-2470**
2. **azure-resource-inventory** (Container App)
3. **Revision management** → **Create new revision**
4. **Container** section → Update image to: `rkazureinventory.azurecr.io/azure-resource-inventory:v4.1`
   - (Once Docker build issues are resolved)

### Option 3: Remove Force Device Login Feature
The main page still has all the UI improvements:
- ✅ Disabled run button until device login checked
- ✅ Security messaging about credentials
- ✅ Development mode detection

The regular `/run` route with device login checkbox works fine.

## Current Status
- **Main page**: ✅ Working with new UI
- **Regular device login**: ✅ Working
- **Force device login page**: ❌ 500 error (optional feature)

## Recommendation
Use the main page with "Use Device Login" checkbox - it has all the same functionality without the problematic separate route.