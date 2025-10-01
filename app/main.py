from flask import Flask, render_template_string, request, redirect, url_for
import os
import subprocess
import shlex


app = Flask(__name__)


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


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    app.run(host="0.0.0.0", port=port)

