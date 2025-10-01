@app.route("/cli-resource-inventory", methods=["GET", "POST"])
def cli_resource_inventory():
    """Alternative approach using pure Azure CLI for resource inventory"""
    if request.method == "GET":
        return '''<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Azure CLI Resource Inventory - Azure Resource Inventory</title>
    <style>
      body { font-family: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif; margin: 40px; }
      .card { max-width: 720px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; }
      h1 { margin-top: 0; color: #0078d4; }
      .warning { padding: 15px; background-color: #e3f2fd; border: 1px solid #2196f3; border-radius: 8px; margin: 20px 0; }
      .form-group { margin-bottom: 20px; }
      label { display: block; margin-bottom: 8px; font-weight: 500; }
      input, select { width: 100%; padding: 10px; border: 1px solid #d1d5db; border-radius: 6px; }
      button { background-color: #0078d4; color: white; padding: 12px 24px; border: none; border-radius: 6px; cursor: pointer; }
      button:hover { background-color: #106ebe; }
      .link { margin-top: 12px; }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>🔧 Azure CLI Resource Inventory</h1>
      
      <div class="warning">
        <strong>Pure CLI Approach:</strong> This method uses only Azure CLI commands to generate a basic resource inventory.
        After authentication, it will list all your Azure resources using CLI commands.
      </div>
      
      <form method="POST">
        <div class="form-group">
          <label for="tenant">Tenant ID (optional):</label>
          <input type="text" name="tenant" id="tenant" placeholder="Leave empty for default tenant">
        </div>
        
        <div class="form-group">
          <label for="subscription">Subscription ID (optional):</label>
          <input type="text" name="subscription" id="subscription" placeholder="Leave empty for default subscription">
        </div>
        
        <button type="submit">Start CLI Resource Inventory</button>
        
        <div class="link">
          <a href="/">← Back to Main Page</a>
        </div>
      </form>
    </div>
  </body>
</html>'''
    
    # POST request - start CLI resource inventory
    tenant = request.form.get("tenant", "").strip() or None
    subscription = request.form.get("subscription", "").strip() or None
    
    job_id = str(uuid.uuid4())
    output_dir = get_output_dir()
    
    # Generate Azure CLI resource inventory script
    cli_script = generate_cli_resource_inventory_script(output_dir, tenant, subscription)
    
    jobs[job_id] = {
        'status': 'running',
        'output': '',
        'created_at': datetime.now(),
        'process': None
    }
    
    # Start CLI job
    thread = threading.Thread(target=run_cli_job, args=(job_id, cli_script))
    thread.daemon = True
    thread.start()
    
    return f'''<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>CLI Resource Inventory - Running</title>
    <style>
      body {{ font-family: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif; margin: 40px; }}
      .card {{ max-width: 720px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; }}
      h1 {{ margin-top: 0; color: #0078d4; }}
      .spinner {{ display: inline-block; width: 20px; height: 20px; border: 3px solid #f3f3f3; border-top: 3px solid #0078d4; border-radius: 50%; animation: spin 2s linear infinite; margin-right: 10px; }}
      @keyframes spin {{ 0% {{ transform: rotate(0deg); }} 100% {{ transform: rotate(360deg); }} }}
      .output {{ background: #1e293b; color: #e2e8f0; padding: 15px; border-radius: 8px; font-family: monospace; white-space: pre-wrap; max-height: 400px; overflow-y: auto; margin-top: 10px; }}
    </style>
  </head>
  <body>
    <div class="card">
      <h1>🔧 CLI Resource Inventory</h1>
      <div style="color: #0078d4;">
        <span class="spinner"></span>
        Running Azure CLI resource inventory...
      </div>
      <div id="output" class="output"></div>
      
      <script>
        const jobId = '{job_id}';
        function checkOutput() {{
          fetch(`/job-status/${{jobId}}`)
            .then(response => response.json())
            .then(data => {{
              const outputElement = document.getElementById('output');
              outputElement.innerHTML = data.output || '';
              outputElement.scrollTop = outputElement.scrollHeight;
              
              if (data.status !== 'running') {{
                clearInterval(interval);
                if (data.status === 'completed') {{
                  window.location.href = '/outputs';
                }}
              }}
            }});
        }}
        const interval = setInterval(checkOutput, 2000);
        checkOutput();
      </script>
    </div>
  </body>
</html>'''


def generate_cli_resource_inventory_script(output_dir, tenant, subscription):
    """Generate bash script using only Azure CLI for resource inventory"""
    script_parts = [
        "#!/bin/bash",
        "set -e",
        f"OUT_DIR='{output_dir}'",
        "mkdir -p \"$OUT_DIR\"",
        "",
        "echo '🔧 AZURE CLI RESOURCE INVENTORY'",
        "echo '=============================='",
        "",
        "# Ensure we're authenticated",
        "echo 'Checking Azure CLI authentication...'",
        "if ! az account show &>/dev/null; then",
        "    echo 'Not authenticated. Starting device login...'",
        "    az login --use-device-code",
        "fi",
        "",
        "echo 'Authentication confirmed!'",
        "az account show",
        "",
    ]
    
    if subscription:
        script_parts.extend([
            f"echo 'Setting subscription: {subscription}'",
            f"az account set --subscription '{subscription}'"
        ])
    
    script_parts.extend([
        "",
        "# Generate resource inventory using Azure CLI",
        "echo 'Generating Azure Resource Inventory...'",
        "",
        "# Get basic account info",
        "echo 'Account Information:' > \"$OUT_DIR/azure-resource-inventory.txt\"",
        "az account show >> \"$OUT_DIR/azure-resource-inventory.txt\"",
        "echo '' >> \"$OUT_DIR/azure-resource-inventory.txt\"",
        "",
        "# List all resource groups",
        "echo 'Resource Groups:' >> \"$OUT_DIR/azure-resource-inventory.txt\"",
        "az group list --output table >> \"$OUT_DIR/azure-resource-inventory.txt\"",
        "echo '' >> \"$OUT_DIR/azure-resource-inventory.txt\"",
        "",
        "# List all resources",
        "echo 'All Resources:' >> \"$OUT_DIR/azure-resource-inventory.txt\"",
        "az resource list --output table >> \"$OUT_DIR/azure-resource-inventory.txt\"",
        "echo '' >> \"$OUT_DIR/azure-resource-inventory.txt\"",
        "",
        "# Export detailed resource info as JSON",
        "echo 'Exporting detailed resource information...'",
        "az resource list --output json > \"$OUT_DIR/resources-detailed.json\"",
        "",
        "# Export resource groups as JSON", 
        "az group list --output json > \"$OUT_DIR/resource-groups.json\"",
        "",
        "# Generate CSV for Excel compatibility",
        "echo 'Generating CSV export...'",
        "az resource list --query '[].{Name:name,Type:type,ResourceGroup:resourceGroup,Location:location}' --output tsv > \"$OUT_DIR/resources.csv\"",
        "",
        "# Add CSV headers",
        "echo -e 'Name\\tType\\tResourceGroup\\tLocation' > \"$OUT_DIR/resources-with-headers.csv\"",
        "cat \"$OUT_DIR/resources.csv\" >> \"$OUT_DIR/resources-with-headers.csv\"",
        "",
        "echo 'Azure CLI Resource Inventory completed!'",
        "echo 'Files generated:'",
        "ls -la \"$OUT_DIR/\"",
    ])
    
    return "\n".join(script_parts)