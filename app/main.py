from flask import Flask, render_template_string, request, redirect, url_for
import os
import subprocess
import shlex
import threading
import uuid
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
    <title>Azure Resource Inventory (ARI) - Runner</title>
    <style>
      body { font-family: system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif; margin: 40px; }
      .card { max-width: 720px; margin: 0 auto; padding: 24px; border: 1px solid #e5e7eb; border-radius: 12px; }
      h1 { margin-top: 0; }
      label { display: block; margin-top: 12px; font-weight: 600; }
      input[type=text] { width: 100%; padding: 10px; border: 1px solid #cbd5e1; border-radius: 8px; }
      .row { display: flex; gap: 12px; }
      .row > div { flex: 1; }
      button { margin-top: 16px; padding: 10px 16px; background: #2563eb; color: white; border: none; border-radius: 8px; cursor: pointer; }
      button:disabled { background: #94a3b8; cursor: not-allowed; }
      .note { color: #475569; font-size: 14px; margin-top: 6px; }
      .success { color: #166534; margin-top: 12px; }
      .error { color: #991b1b; margin-top: 12px; }
      .link { margin-top: 12px; }
      .muted { color: #64748b; }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Run Azure Resource Inventory</h1>
      <p class="muted">Containerized one-click runner for the Azure Resource Inventory PowerShell module.</p>
      <form method="post" action="{{ url_for('run_job') }}">
        <label for="tenant">Tenant ID (optional)</label>
        <input id="tenant" name="tenant" type="text" placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" />

        <div class="row">
          <div>
            <label for="subscription">Subscription ID (optional)</label>
            <input id="subscription" name="subscription" type="text" placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" />
          </div>
          <div>
            <label for="reportname">Report Name (optional)</label>
            <input id="reportname" name="reportname" type="text" placeholder="AzureResourceInventory" />
          </div>
        </div>

        <label for="include_tags">
          <input id="include_tags" name="include_tags" type="checkbox" /> Include Tags
        </label>
        <label for="skip_advisory">
          <input id="skip_advisory" name="skip_advisory" type="checkbox" /> Skip Azure Advisor
        </label>
        <label for="skip_diagram">
          <input id="skip_diagram" name="skip_diagram" type="checkbox" /> Skip Diagram
        </label>

        <label for="device_login">
          <input id="device_login" name="device_login" type="checkbox" /> Use Device Login (interactive)
        </label>

        <button type="submit">Run Invoke-ARI</button>
      </form>

      {% if message %}
        <div class="{{ 'success' if success else 'error' }}">{{ message }}</div>
      {% endif %}
      <div class="link"><a href="{{ url_for('list_outputs') }}">View generated reports</a></div>
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
    return render_template_string(INDEX_HTML, message=None)


@app.route("/run", methods=["POST"])
def run_job():
    output_dir = get_output_dir()

    tenant = (request.form.get("tenant") or "").strip()
    subscription = (request.form.get("subscription") or "").strip()
    reportname = (request.form.get("reportname") or "AzureResourceInventory").strip()
    include_tags = request.form.get("include_tags") == "on"
    skip_advisory = request.form.get("skip_advisory") == "on"
    skip_diagram = request.form.get("skip_diagram") == "on"
    device_login = request.form.get("device_login") == "on"

    pwsh_cmd = [
        "pwsh",
        "-NoProfile",
        "-Command",
    ]

    ps_script_parts = [
        "Import-Module AzureResourceInventory -Force;",
        f"$ErrorActionPreference='Stop';",
        f"$out='{output_dir}';",
        "New-Item -ItemType Directory -Force -Path $out | Out-Null;",
        "Invoke-ARI",
        f" -ReportDir \"{output_dir}\"",
        f" -ReportName \"{reportname}\"",
    ]

    if tenant:
        ps_script_parts.append(f" -TenantID \"{shlex.quote(tenant)}\"")
    if subscription:
        ps_script_parts.append(f" -SubscriptionID \"{shlex.quote(subscription)}\"")
    if include_tags:
        ps_script_parts.append(" -IncludeTags")
    if skip_advisory:
        ps_script_parts.append(" -SkipAdvisory")
    if skip_diagram:
        ps_script_parts.append(" -SkipDiagram")
    if device_login:
        ps_script_parts.append(" -DeviceLogin")

    ps_script = "".join(ps_script_parts)

    try:
        result = subprocess.run(pwsh_cmd + [ps_script], capture_output=True, text=True, timeout=60 * 60)
        success = result.returncode == 0
        message = (result.stdout or "")[-2000:]
        if not success:
            message = (result.stderr or message)[-2000:]
        return render_template_string(INDEX_HTML, message=message, success=success)
    except subprocess.TimeoutExpired:
        return render_template_string(INDEX_HTML, message="Timed out after 60 minutes.", success=False)


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
        enhanced = f"🌐 <strong>{line.strip()}</strong>\n"
    elif "https://microsoft.com/devicelogin" in line:
        url = "https://microsoft.com/devicelogin"
        enhanced = f'📱 <strong>Open: <a href="{url}" target="_blank" style="color: #0078d4;">{url}</a></strong>\n'
    elif re.search(r'\b[A-Z0-9]{4}-[A-Z0-9]{4}\b', line):
        # Device code pattern like "XXXX-XXXX"
        match = re.search(r'\b([A-Z0-9]{4}-[A-Z0-9]{4})\b', line)
        if match:
            code = match.group(1)
            enhanced = f'🔑 <span style="background-color: yellow; padding: 4px 8px; font-size: 18px; font-weight: bold; border-radius: 4px;">{code}</span> <- YOUR DEVICE CODE\n'
        else:
            enhanced = line
    elif "Continuing will" in line or "complete the authentication" in line:
        enhanced = f"ℹ️ <em>{line.strip()}</em>\n"
    else:
        enhanced = line
    
    return enhanced


@app.route("/cli-device-login", methods=["GET", "POST"])
def cli_device_login():
    """Azure CLI device login for Azure Resource Inventory"""
    if request.method == "GET":
        # Get parameters from URL if provided
        tenant_param = request.args.get("tenant", "") or ""
        subscription_param = request.args.get("subscription", "") or ""
        
        # Create HTML template without f-string to avoid CSS issues
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
      <h1>🚀 Azure Resource Inventory - Device Login</h1>
      
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
          <a href="/">← Back to Main Page</a>
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
      <h1>🚀 Azure CLI Device Login</h1>
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


def generate_cli_device_login_script(output_dir, tenant, subscription):
    """Generate bash script using Azure CLI for device login"""
    script_parts = [
        "#!/bin/bash",
        "set -e",
        f"OUT_DIR='{output_dir}'",
        "mkdir -p \"$OUT_DIR\"",
        "",
        "echo '🔧 AZURE CLI DEVICE LOGIN BYPASS'",
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
        jobs[job_id]['output'] += "Starting Azure CLI device login process...\n"
        
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
            jobs[job_id]['output'] += "\n✅ Azure CLI device login completed successfully!"
        else:
            jobs[job_id]['status'] = 'failed'
            jobs[job_id]['output'] += f"\n❌ Azure CLI device login failed with exit code {process.returncode}"
            
    except Exception as e:
        jobs[job_id]['status'] = 'failed'
        jobs[job_id]['output'] += f"\n❌ Error: {str(e)}"


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    app.run(host="0.0.0.0", port=port)

