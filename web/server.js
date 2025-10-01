const express = require('express');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs').promises;
const multer = require('multer');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname)));

// Storage configuration
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, '/tmp/uploads/');
    },
    filename: (req, file, cb) => {
        cb(null, file.originalname);
    }
});

const upload = multer({ storage });

// Ensure directories exist
async function ensureDirectories() {
    const dirs = ['/tmp/uploads', '/tmp/reports'];
    for (const dir of dirs) {
        try {
            await fs.mkdir(dir, { recursive: true });
        } catch (error) {
            console.error(`Error creating directory ${dir}:`, error);
        }
    }
}

// PowerShell execution helper
function executePowerShell(command, args = []) {
    return new Promise((resolve, reject) => {
        console.log(`Executing: pwsh -Command "${command}"`);
        
        const ps = spawn('pwsh', ['-Command', command], {
            stdio: ['pipe', 'pipe', 'pipe'],
            env: {
                ...process.env,
                PSModulePath: '/opt/microsoft/powershell/7/Modules:/usr/local/share/powershell/Modules:/opt/microsoft/powershell/7/Modules'
            }
        });

        let stdout = '';
        let stderr = '';

        ps.stdout.on('data', (data) => {
            stdout += data.toString();
            console.log('STDOUT:', data.toString());
        });

        ps.stderr.on('data', (data) => {
            stderr += data.toString();
            console.log('STDERR:', data.toString());
        });

        ps.on('close', (code) => {
            console.log(`PowerShell process exited with code ${code}`);
            if (code === 0) {
                resolve({ stdout, stderr });
            } else {
                reject(new Error(`PowerShell exited with code ${code}: ${stderr}`));
            }
        });

        ps.on('error', (error) => {
            console.error('PowerShell spawn error:', error);
            reject(error);
        });
    });
}

// API Routes

// Health check
app.get('/api/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Check PowerShell and modules
app.get('/api/check-environment', async (req, res) => {
    try {
        // Check PowerShell version
        const psVersion = await executePowerShell('$PSVersionTable.PSVersion.ToString()');
        
        // Check if ARI module is available
        const ariCheck = await executePowerShell('Get-Module -ListAvailable -Name AzureResourceInventory | Select-Object Name, Version');
        
        // Check Azure modules
        const azModules = await executePowerShell('Get-Module -ListAvailable -Name Az.* | Select-Object Name, Version | Sort-Object Name');
        
        res.json({
            powershell: psVersion.stdout.trim(),
            ariModule: ariCheck.stdout.trim(),
            azureModules: azModules.stdout.trim()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Generate inventory
app.post('/api/generate-inventory', async (req, res) => {
    const {
        tenantId,
        subscriptionId,
        appId,
        secret,
        reportName = 'AzureResourceInventory',
        azureEnvironment = 'AzureCloud',
        includeTags = false,
        securityCenter = false,
        skipDiagram = false,
        skipAdvisory = false,
        lite = false,
        debug = false
    } = req.body;

    // Set response headers for Server-Sent Events
    res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Cache-Control'
    });

    function sendEvent(type, data) {
        res.write(`data: ${JSON.stringify({ type, ...data })}\n\n`);
    }

    try {
        sendEvent('log', { message: 'Starting Azure Resource Inventory generation...' });
        sendEvent('progress', { percent: 10 });

        // Validate required parameters
        if (!tenantId) {
            throw new Error('Tenant ID is required');
        }

        // Build PowerShell command
        let command = `
            Import-Module AzureResourceInventory -Force;
            $ErrorActionPreference = 'Stop';
            
            # Set report directory
            $ReportDir = '/tmp/reports';
            if (!(Test-Path $ReportDir)) {
                New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null;
            }
            
            # Build parameters
            $params = @{
                TenantID = '${tenantId}';
                ReportDir = $ReportDir;
                ReportName = '${reportName}';
                AzureEnvironment = '${azureEnvironment}';
        `;

        if (subscriptionId) {
            command += `        SubscriptionID = '${subscriptionId}';\n`;
        }

        if (appId && secret) {
            command += `        AppId = '${appId}';\n`;
            command += `        Secret = '${secret}';\n`;
        }

        if (includeTags) command += `        IncludeTags = $true;\n`;
        if (securityCenter) command += `        SecurityCenter = $true;\n`;
        if (skipDiagram) command += `        SkipDiagram = $true;\n`;
        if (skipAdvisory) command += `        SkipAdvisory = $true;\n`;
        if (lite) command += `        Lite = $true;\n`;
        if (debug) command += `        Debug = $true;\n`;

        command += `    }
            
            Write-Host "Connecting to Azure...";
            Write-Host "Parameters: $($params | ConvertTo-Json -Depth 2)";
            
            try {
                Invoke-ARI @params;
                Write-Host "Azure Resource Inventory completed successfully!";
                
                # List generated files
                $files = Get-ChildItem -Path $ReportDir -File | Select-Object Name, Length, LastWriteTime;
                $files | ForEach-Object { Write-Host "Generated: $($_.Name) ($($_.Length) bytes)" };
            }
            catch {
                Write-Error "Error executing ARI: $($_.Exception.Message)";
                throw;
            }
        `;

        sendEvent('log', { message: 'Executing PowerShell command...' });
        sendEvent('progress', { percent: 20 });

        // Execute PowerShell command
        const ps = spawn('pwsh', ['-Command', command], {
            stdio: ['pipe', 'pipe', 'pipe'],
            env: {
                ...process.env,
                PSModulePath: '/opt/microsoft/powershell/7/Modules:/usr/local/share/powershell/Modules:/opt/microsoft/powershell/7/Modules'
            }
        });

        let progress = 30;

        ps.stdout.on('data', (data) => {
            const output = data.toString();
            sendEvent('log', { message: output });
            
            // Update progress based on output
            if (output.includes('Connecting to Azure')) {
                progress = 40;
            } else if (output.includes('Processing')) {
                progress = Math.min(progress + 5, 80);
            } else if (output.includes('Generating')) {
                progress = Math.min(progress + 5, 90);
            }
            
            sendEvent('progress', { percent: progress });
        });

        ps.stderr.on('data', (data) => {
            const error = data.toString();
            sendEvent('log', { message: `ERROR: ${error}` });
        });

        ps.on('close', async (code) => {
            if (code === 0) {
                try {
                    // List generated files
                    const files = await fs.readdir('/tmp/reports');
                    const fileDetails = [];
                    
                    for (const file of files) {
                        const stats = await fs.stat(path.join('/tmp/reports', file));
                        fileDetails.push({
                            name: file,
                            size: stats.size,
                            modified: stats.mtime
                        });
                    }
                    
                    sendEvent('complete', { files: fileDetails });
                } catch (error) {
                    sendEvent('error', { message: `Error listing files: ${error.message}` });
                }
            } else {
                sendEvent('error', { message: `PowerShell process exited with code ${code}` });
            }
        });

        ps.on('error', (error) => {
            sendEvent('error', { message: `Process error: ${error.message}` });
        });

    } catch (error) {
        console.error('Error in generate-inventory:', error);
        sendEvent('error', { message: error.message });
    }
});

// Download generated files
app.get('/api/download/:filename', async (req, res) => {
    try {
        const filename = req.params.filename;
        const filePath = path.join('/tmp/reports', filename);
        
        // Check if file exists
        await fs.access(filePath);
        
        // Set appropriate headers
        res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
        
        // Determine content type based on file extension
        const ext = path.extname(filename).toLowerCase();
        if (ext === '.xlsx') {
            res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        } else if (ext === '.xml') {
            res.setHeader('Content-Type', 'application/xml');
        } else {
            res.setHeader('Content-Type', 'application/octet-stream');
        }
        
        // Stream the file
        const fileStream = require('fs').createReadStream(filePath);
        fileStream.pipe(res);
        
    } catch (error) {
        console.error('Error downloading file:', error);
        res.status(404).json({ error: 'File not found' });
    }
});

// List available reports
app.get('/api/reports', async (req, res) => {
    try {
        const files = await fs.readdir('/tmp/reports');
        const fileDetails = [];
        
        for (const file of files) {
            const stats = await fs.stat(path.join('/tmp/reports', file));
            fileDetails.push({
                name: file,
                size: stats.size,
                modified: stats.mtime
            });
        }
        
        res.json(fileDetails);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Error handling middleware
app.use((error, req, res, next) => {
    console.error('Unhandled error:', error);
    res.status(500).json({ error: 'Internal server error' });
});

// Start server
async function startServer() {
    await ensureDirectories();
    
    app.listen(PORT, '0.0.0.0', () => {
        console.log(`ARI Web Interface server running on port ${PORT}`);
        console.log(`Access the application at: http://localhost:${PORT}`);
    });
}

startServer().catch(console.error);