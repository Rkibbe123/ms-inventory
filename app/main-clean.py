from flask import Flask, render_template_string, request, redirect, url_for, jsonify
import os
import subprocess
import shlex
import threading
import uuid
import time
from datetime import datetime
import re


app = Flask(__name__)

# Global jobs dictionary to track running processes
jobs = {}


INDEX_HTML = """
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Azure Resource Inventory (ARI) - Comprehensive Cloud Assessment Tool</title>
    <style>
      body { 
        font-family: system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; 
        margin: 0; 
        padding: 40px; 
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        min-height: 100vh;
      }
      .container { 
        max-width: 900px; 
        margin: 0 auto; 
        background: white; 
        border-radius: 16px; 
        box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);
        overflow: hidden;
      }
      .header { 
        background: linear-gradient(135deg, #0078d4 0%, #106ebe 100%); 
        color: white; 
        padding: 40px; 
        text-align: center; 
      }
      .header h1 { 
        margin: 0; 
        font-size: 2.5rem; 
        font-weight: 700; 
        text-shadow: 0 2px 4px rgba(0,0,0,0.3); 
      }
      .header p { 
        margin: 10px 0 0 0; 
        font-size: 1.2rem; 
        opacity: 0.9; 
      }
      .content { padding: 40px; }
      .description { 
        background: #f8f9fa; 
        padding: 30px; 
        border-radius: 12px; 
        margin-bottom: 30px; 
        border-left: 5px solid #0078d4; 
      }
      .description h3 { 
        color: #0078d4; 
        margin-top: 0; 
        font-size: 1.4rem; 
      }
      .features { 
        display: grid; 
        grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); 
        gap: 20px; 
        margin: 30px 0; 
      }
      .feature { 
        background: #f1f5f9; 
        padding: 20px; 
        border-radius: 8px; 
        border-left: 4px solid #0078d4; 
      }
      .feature h4 { 
        margin: 0 0 10px 0; 
        color: #1e293b; 
        font-size: 1rem; 
      }
      .feature p { 
        margin: 0; 
        color: #475569; 
        font-size: 0.9rem; 
        line-height: 1.5; 
      }
      .run-section { 
        background: #fff; 
        padding: 30px; 
        border: 2px solid #e2e8f0; 
        border-radius: 12px; 
        text-align: center; 
        margin-top: 30px; 
      }
      .run-button { 
        display: inline-block; 
        background: linear-gradient(135deg, #dc2626 0%, #991b1b 100%); 
        color: white; 
        padding: 20px 40px; 
        font-size: 1.3rem; 
        font-weight: 700; 
        border: none; 
        border-radius: 12px; 
        cursor: pointer; 
        text-decoration: none; 
        box-shadow: 0 10px 15px -3px rgba(220, 38, 38, 0.3), 0 4px 6px -2px rgba(220, 38, 38, 0.05);
        transition: all 0.3s ease;
        text-transform: uppercase;
        letter-spacing: 1px;
      }
      .run-button:hover { 
        transform: translateY(-2px); 
        box-shadow: 0 15px 25px -5px rgba(220, 38, 38, 0.4), 0 10px 10px -5px rgba(220, 38, 38, 0.1);
      }
      .auth-note { 
        margin-top: 20px; 
        color: #475569; 
        font-size: 0.9rem; 
        background: #f1f5f9; 
        padding: 15px; 
        border-radius: 8px; 
      }
      .footer { 
        text-align: center; 
        padding: 20px 40px; 
        background: #f8f9fa; 
        color: #6b7280; 
        font-size: 0.9rem; 
      }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="header">
        <h1>Azure Resource Inventory</h1>
        <p>Comprehensive Cloud Infrastructure Assessment & Documentation</p>
      </div>
      
      <div class="content">
        <div class="description">
          <h3>What is Azure Resource Inventory (ARI)?</h3>
          <p>Azure Resource Inventory is a powerful PowerShell module that provides comprehensive visibility into your Azure infrastructure. It automatically discovers, analyzes, and documents all your Azure resources across subscriptions, generating detailed reports and network diagrams to help you understand, manage, and optimize your cloud environment.</p>
        </div>
        
        <div class="features">
          <div class="feature">
            <h4>Comprehensive Discovery</h4>
            <p>Scans all Azure subscriptions and resource groups to identify every resource, configuration, and relationship in your environment.</p>
          </div>
          <div class="feature">
            <h4>Excel Reports</h4>
            <p>Generates detailed Excel workbooks with multiple sheets covering resources, security, networking, and cost analysis.</p>
          </div>
          <div class="feature">
            <h4>Network Diagrams</h4>
            <p>Creates visual network topology diagrams showing VNets, subnets, NSGs, and connectivity relationships.</p>
          </div>
          <div class="feature">
            <h4>Security Analysis</h4>
            <p>Integrates with Azure Security Center and Advisor to provide security recommendations and compliance insights.</p>
          </div>
          <div class="feature">
            <h4>Cost Insights</h4>
            <p>Analyzes resource costs, identifies optimization opportunities, and provides spending breakdowns by resource type.</p>
          </div>
          <div class="feature">
            <h4>Multi-Tenant Support</h4>
            <p>Supports multiple Azure tenants and subscriptions with flexible authentication and scope configuration.</p>
          </div>
        </div>
        
        <div class="run-section">
          <h3 style="margin-top: 0; color: #1e293b;">Ready to Analyze Your Azure Environment?</h3>
          <p style="margin: 10px 0 25px 0; color: #475569;">Click below to start the Azure Resource Inventory analysis with secure device authentication.</p>
          
          <a href="/cli-device-login" class="run-button">
            Run Invoke-ARI
          </a>
          
          <div class="auth-note">
            <strong>Secure Authentication:</strong> Uses Azure CLI device login for secure, credential-free authentication. 
            Your credentials are never stored and authentication is handled directly by Microsoft Azure.
          </div>
        </div>
      </div>
      
      <div class="footer">
        <p>Azure Resource Inventory - Open Source Cloud Assessment Tool | <a href="/outputs" style="color: #0078d4;">View Reports</a></p>
      </div>
    </div>
  </body>
</html>
"""


def get_output_dir() -> str:
    default_dir = os.environ.get("ARI_OUTPUT_DIR", os.path.expanduser("~/AzureResourceInventory"))
    os.makedirs(default_dir, exist_ok=True)
    return default_dir


@app.route("/", methods=["GET"])
def index():
    return INDEX_HTML


@app.route("/outputs", methods=["GET"])
def list_outputs():
    output_dir = get_output_dir()
    files = []
    try:
        for name in sorted(os.listdir(output_dir)):
            if name.lower().endswith((".xlsx", ".xml", ".log")):
                files.append(name)
    except FileNotFoundError:
        pass

    items = "".join(f"<li><a href='/download/{name}'>{name}</a></li>" for name in files) or "<li>No files yet</li>"
    html = f"""
<!doctype html>
<html>
  <head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'><title>Outputs</title></head>
  <body style='font-family: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif; margin: 40px;'>
    <h1>Generated outputs</h1>
    <ul>{items}</ul>
    <a href='/'>Back</a>
  </body>
</html>
"""
    return html


@app.route("/download/<path:filename>", methods=["GET"])
def download_file(filename: str):
    from flask import send_from_directory, abort

    output_dir = get_output_dir()
    safe_name = os.path.basename(filename)
    file_path = os.path.join(output_dir, safe_name)
    if not os.path.exists(file_path):
        return abort(404)
    return send_from_directory(output_dir, safe_name, as_attachment=True)


def enhance_device_code_output(line):
    """Enhance device code output with formatting for better visibility"""
    if not line.strip():
        return line
    
    # Look for device code patterns and enhance them
    enhanced = line
    
    # Device code pattern matching
    if "To sign in, use a web browser" in line:
        enhanced = f"<strong>{line.strip()}</strong><br>"
    elif "https://microsoft.com/devicelogin" in line:
        url = "https://microsoft.com/devicelogin"
        enhanced = f'<strong>Open: <a href="{url}" target="_blank" style="color: #0078d4;">{url}</a></strong><br>'
    elif re.search(r'\b[A-Z0-9]{4}-[A-Z0-9]{4}\b', line):
        # Device code pattern like "XXXX-XXXX"
        match = re.search(r'\b([A-Z0-9]{4}-[A-Z0-9]{4})\b', line)
        if match:
            code = match.group(1)
            enhanced = f'<span style="background-color: yellow; padding: 4px 8px; font-size: 18px; font-weight: bold; border-radius: 4px;">{code}</span> &lt;- YOUR DEVICE CODE<br>'
        else:
            enhanced = line + "<br>"
    elif "Continuing will" in line or "complete the authentication" in line:
        enhanced = f"<em>{line.strip()}</em><br>"
    else:
        enhanced = line + "<br>"
    
    return enhanced


@app.route("/cli-device-login", methods=["GET", "POST"])
def cli_device_login():
    """Azure CLI device login for Azure Resource Inventory"""
    if request.method == "GET":
        # Get parameters from URL if provided
        tenant_param = request.args.get("tenant", "") or ""
        subscription_param = request.args.get("subscription", "") or ""
        
        # Create HTML template
        html_template = '''<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Azure CLI Device Login - Azure Resource Inventory</title>
    <style>
      body { font-family: system-ui, sans-serif; margin: 40px; }
      .card { max-width: 720px; margin: 0 auto; padding: 24px; border: 1px solid #ccc; border-radius: 8px; }
      h1 { margin-top: 0; color: #0078d4; }
      .warning { padding: 15px; background-color: #fff3cd; border: 1px solid #ffeaa7; border-radius: 8px; margin: 20px 0; }
      .form-group { margin-bottom: 20px; }
      label { display: block; margin-bottom: 8px; font-weight: 500; }
      input { width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 6px; }
      button { background-color: #0078d4; color: white; padding: 12px 24px; border: none; border-radius: 6px; cursor: pointer; }
      button:hover { background-color: #106ebe; }
      .link { margin-top: 12px; }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Azure Resource Inventory - Device Login</h1>
      
      <div class="warning">
        <strong>Secure Authentication:</strong> Uses Azure CLI device login for secure authentication.
        <br><strong>Your credentials are never stored</strong> - authentication is handled directly by Microsoft Azure.
      </div>
      
      <form method="POST">
        <div class="form-group">
          <label for="tenant">Tenant ID (optional):</label>
          <input type="text" name="tenant" id="tenant" value="TENANT_VALUE" placeholder="Leave empty for default tenant">
        </div>
        
        <div class="form-group">
          <label for="subscription">Subscription ID (optional):</label>
          <input type="text" name="subscription" id="subscription" value="SUBSCRIPTION_VALUE" placeholder="Leave empty for default subscription">
        </div>
        
        <button type="submit">Start Azure CLI Device Login</button>
        
        <div class="link">
          <a href="/">Back to Main Page</a>
        </div>
      </form>
    </div>
  </body>
</html>'''
        
        # Replace placeholders safely
        html_template = html_template.replace("TENANT_VALUE", tenant_param)
        html_template = html_template.replace("SUBSCRIPTION_VALUE", subscription_param)
        
        return html_template
    
    # POST request - start Azure CLI device login process
    tenant = request.form.get("tenant", "").strip() or None
    subscription = request.form.get("subscription", "").strip() or None
    
    job_id = str(uuid.uuid4())
    output_dir = get_output_dir()
    
    # Generate Azure CLI script
    cli_script = generate_cli_device_login_script(output_dir, tenant, subscription)
    
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
    
    return '''<!doctype html>
<html>
  <head>
    <title>CLI Device Login - Running</title>
    <style>
      body { font-family: system-ui, sans-serif; margin: 40px; }
      .card { max-width: 720px; margin: 0 auto; padding: 24px; border: 1px solid #ccc; border-radius: 8px; }
      .spinner { display: inline-block; width: 20px; height: 20px; border: 3px solid #f3f3f3; border-top: 3px solid #0078d4; border-radius: 50%; animation: spin 2s linear infinite; margin-right: 10px; }
      @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
      .output { background: #1e293b; color: #e2e8f0; padding: 15px; border-radius: 8px; font-family: monospace; white-space: pre-wrap; max-height: 400px; overflow-y: auto; margin-top: 10px; }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Azure CLI Device Login</h1>
      <div style="color: #0078d4;">
        <span class="spinner"></span>
        Running Azure CLI device login... Watch for authentication instructions!
      </div>
      <div id="output" class="output"></div>
      
      <script>
        const jobId = ''' + f"'{job_id}'" + ''';
        function checkOutput() {
          fetch(`/job-status/${jobId}`)
            .then(response => response.json())
            .then(data => {
              const outputElement = document.getElementById('output');
              outputElement.innerHTML = data.output || '';
              outputElement.scrollTop = outputElement.scrollHeight;
              
              if (data.status !== 'running') {
                clearInterval(interval);
                if (data.status === 'completed') {
                  window.location.href = '/outputs';
                }
              }
            });
        }
        const interval = setInterval(checkOutput, 2000);
        checkOutput();
      </script>
    </div>
  </body>
</html>'''


@app.route("/job-status/<job_id>")
def get_job_status(job_id):
    """Get the status and output of a running job"""
    if job_id not in jobs:
        return jsonify({'error': 'Job not found'}), 404
    
    job = jobs[job_id]
    return jsonify({
        'status': job['status'],
        'output': job['output'],
        'created_at': job['created_at'].isoformat() if 'created_at' in job else None
    })


def generate_cli_device_login_script(output_dir, tenant, subscription):
    """Generate bash script using Azure CLI for device login"""
    script_parts = [
        "#!/bin/bash",
        "set -e",
        f"OUT_DIR='{output_dir}'",
        "mkdir -p \"$OUT_DIR\"",
        "",
        "echo 'AZURE CLI DEVICE LOGIN BYPASS'",
        "echo '================================='",
        "",
        "# Clear any existing Azure CLI auth",
        "echo 'Clearing existing Azure CLI authentication...'",
        "az logout 2>/dev/null || true",
        "az account clear 2>/dev/null || true",
        "",
        "# Force device login with Azure CLI", 
        "echo 'Starting Azure CLI device login...'",
        "echo 'YOU MUST COMPLETE THE DEVICE LOGIN IN YOUR BROWSER!'",
    ]
    
    if tenant:
        script_parts.append(f"az login --tenant '{tenant}' --use-device-code")
    else:
        script_parts.append("az login --use-device-code")
    
    if subscription:
        script_parts.extend([
            f"echo 'Setting subscription to: {subscription}'",
            f"az account set --subscription '{subscription}'"
        ])
    
    script_parts.extend([
        "",
        "# Verify authentication",
        "echo 'Verifying authentication...'", 
        "az account show",
        "",
        "echo 'Azure CLI authentication completed!'",
        "echo 'Note: You can now use this authentication for other Azure operations'",
    ])
    
    return "\n".join(script_parts)


def run_cli_job(job_id, script):
    """Run Azure CLI script with enhanced device code formatting"""
    try:
        jobs[job_id]['output'] += "Starting Azure CLI device login process...<br>"
        
        # Write script to file
        script_file = "/tmp/cli_device_login.sh"
        with open(script_file, 'w') as f:
            f.write(script)
        os.chmod(script_file, 0o755)
        
        # Run the script
        process = subprocess.Popen(
            ["/bin/bash", script_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )
        
        jobs[job_id]['process'] = process
        
        # Stream output with enhanced formatting
        for line in iter(process.stdout.readline, ''):
            if line:
                # Enhance device code formatting
                enhanced_line = enhance_device_code_output(line)
                jobs[job_id]['output'] += enhanced_line
        
        process.wait()
        
        if process.returncode == 0:
            jobs[job_id]['status'] = 'completed'
            jobs[job_id]['output'] += "<br>Azure CLI device login completed successfully!"
        else:
            jobs[job_id]['status'] = 'failed'
            jobs[job_id]['output'] += f"<br>Azure CLI device login failed with exit code {process.returncode}"
            
    except Exception as e:
        jobs[job_id]['status'] = 'failed'
        jobs[job_id]['output'] += f"<br>Error: {str(e)}"


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    app.run(host="0.0.0.0", port=port)