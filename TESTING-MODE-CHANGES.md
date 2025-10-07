# Testing Mode Changes - Single Module Test

## What Was Changed

To test if the Azure Resource Inventory can complete end-to-end, I've temporarily modified the code to:

1. **Run ONLY the Compute module** instead of all 16+ modules
2. **Skip extra jobs** (Draw.io, Security Center, Policy, Advisory) 
3. **Keep the Subscriptions job** (required for output)
4. **Increase per-job timeout** from 1 minute to 3 minutes

This will help us identify if:
- ✅ The basic processing pipeline works
- ✅ Jobs can complete successfully
- ✅ Reports can be generated
- ❌ There's a fundamental issue causing hangs

## Modified Files

### 1. `Modules\Private\2.ProcessingFunctions\Start-ARIProcessJob.ps1`
**Lines 59-68**: Changed module selection to only process Compute

```powershell
# BEFORE (commented out):
# $ModuleFolders = Get-ChildItem -Path $InventoryModulesPath -Directory

# AFTER (testing mode):
Write-Host "🧪 TESTING MODE: Only processing Compute module for quick validation" -ForegroundColor Yellow
$ModuleFolders = Get-ChildItem -Path $InventoryModulesPath -Directory | Where-Object { $_.Name -eq 'Compute' }
```

### 2. `Modules\Private\2.ProcessingFunctions\Start-ARIExtraJobs.ps1`
**Multiple sections**: Commented out extra jobs

- ❌ Draw.io Diagram Job (commented out)
- ❌ Security Center Job (commented out)  
- ❌ Policy Job (commented out)
- ❌ Advisory Job (commented out)
- ✅ Subscriptions Job (kept - required for output)

### 3. `Modules\Public\PublicFunctions\Jobs\Wait-ARIJob.ps1`
**Lines 23-29**: Adjusted timeout settings

```powershell
# BEFORE:
# $TimeoutMinutes = 10
# $PerJobTimeoutMinutes = 1

# AFTER:
$TimeoutMinutes = 15  # Total timeout for all jobs
$PerJobTimeoutMinutes = 3  # Per-job timeout (increased from 1 to 3 minutes)
```

## What Will Happen

When you run the inventory now:

1. **Authentication** - Same as before
2. **Resource Extraction** - Same as before (fetches ALL resources)
3. **Job Creation** - Creates ONLY 1 job instead of 16+ jobs
   - ✅ Compute module only
4. **Processing** - Processes only Compute resources
5. **Extra Jobs** - Skips most extra jobs
   - ❌ No Draw.io diagrams
   - ❌ No Security analysis
   - ❌ No Policy analysis
   - ❌ No Advisory analysis
   - ✅ Subscriptions processing (needed for Excel output)
6. **Output** - Generates Excel report with limited data

## Expected Results

### Success Case:
- Job completes in 3-5 minutes
- Excel report is generated (with only Compute tab populated)
- We know the pipeline works end-to-end

### Failure Case:
- Job times out after 3 minutes
- Error messages are visible
- We can diagnose the specific issue

## How to Deploy and Test

1. **Build and deploy the container:**
   ```powershell
   .\quick-deploy.ps1
   ```

2. **Start a new scan:**
   - Go to: https://azure-resource-inventory.ambitiousbeach-c62b6a92.eastus.azurecontainerapps.io
   - Click "Run Invoke-ARI"
   - Complete device authentication

3. **Monitor progress:**
   ```powershell
   .\watch-progress.ps1
   # or
   .\check-status-simple.ps1
   ```

4. **Check logs for test indicators:**
   You should see:
   ```
   🧪 TESTING MODE: Only processing Compute module for quick validation
   🧪 TESTING MODE: Skipping Draw.io Diagram Job
   🧪 TESTING MODE: Skipping Security Center Job
   🧪 TESTING MODE: Skipping Policy Job
   🧪 TESTING MODE: Skipping Advisory Job
   ✅ Running Subscriptions Processing job (required for output)
   ```

## How to Restore Full Functionality

Once testing is complete and we identify the issue:

### Option 1: Revert Changes Manually
1. Open `Start-ARIProcessJob.ps1`
2. Uncomment the original line:
   ```powershell
   $ModuleFolders = Get-ChildItem -Path $InventoryModulesPath -Directory
   ```
3. Comment out or remove the testing line

4. Open `Start-ARIExtraJobs.ps1`
5. Uncomment all the job sections (Draw.io, Security, Policy, Advisory)

6. Open `Wait-ARIJob.ps1`
7. Adjust timeouts back to original values if needed

### Option 2: Use Git to Revert
```powershell
git checkout Modules/Private/2.ProcessingFunctions/Start-ARIProcessJob.ps1
git checkout Modules/Private/2.ProcessingFunctions/Start-ARIExtraJobs.ps1
git checkout Modules/Public/PublicFunctions/Jobs/Wait-ARIJob.ps1
```

### Option 3: Search and Replace
Search for `===== TEMPORARY` in all files and remove/uncomment the sections

## Expected Timeline

- **Normal full scan**: 10-30 minutes
- **Testing mode (1 module)**: 3-5 minutes
- **Timeout if stuck**: 3 minutes per job (auto-stops)

## Next Steps After Testing

1. **If it works**: We know the issue is with specific modules or extra jobs
   - Gradually add back modules one at a time
   - Identify which module is causing the hang

2. **If it still hangs**: The issue is fundamental
   - Check PowerShell job execution
   - Check Azure API connectivity
   - Check memory/CPU constraints

3. **If it errors**: We'll see the actual error message
   - Address the specific error
   - Fix the underlying issue

---

**Remember**: All changes are temporary and clearly marked with comments. They can be easily reverted once testing is complete!
