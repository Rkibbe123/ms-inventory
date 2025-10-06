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
        background: linear-gradient(135deg, #1e3c72 0%, #2a5298 50%, #0ea5e9 100%);
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


@app.route("/debug-files", methods=["GET"])
def debug_files():
    """Debug endpoint to check file system status"""
    output_dir = get_output_dir()
    debug_info = {
        "output_dir": output_dir,
        "dir_exists": os.path.exists(output_dir),
        "all_files": [],
        "filtered_files": [],
        "env_var": os.environ.get("ARI_OUTPUT_DIR", "Not set")
    }
    
    try:
        if os.path.exists(output_dir):
            all_files = os.listdir(output_dir)
            debug_info["all_files"] = all_files
            debug_info["filtered_files"] = [f for f in all_files if f.lower().endswith((".xlsx", ".xml", ".log", ".txt", ".csv", ".json", ".html", ".pdf"))]
    except Exception as e:
        debug_info["error"] = str(e)
    
    return f"<pre>{str(debug_info)}</pre>"

@app.route("/outputs", methods=["GET"])
def list_outputs():
    output_dir = get_output_dir()
    files = []
    try:
        for name in sorted(os.listdir(output_dir)):
            if name.lower().endswith((".xlsx", ".xml", ".log", ".txt", ".csv", ".json", ".html", ".pdf")):
                files.append(name)
    except FileNotFoundError:
        pass

    # Create file items with enhanced styling
    if files:
        items = ""
        for name in files:
            # Determine file type and icon
            ext = name.lower().split('.')[-1] if '.' in name else ''
            if ext == 'xlsx':
                icon = "📊"
                type_label = "Excel Report"
            elif ext == 'xml':
                icon = "🌐"
                type_label = "XML Data"
            elif ext == 'log':
                icon = "📝"
                type_label = "Log File"
            elif ext == 'txt':
                icon = "📄"
                type_label = "Text File"
            elif ext == 'csv':
                icon = "📋"
                type_label = "CSV Data"
            elif ext == 'json':
                icon = "🔗"
                type_label = "JSON Data"
            elif ext == 'html':
                icon = "🌐"
                type_label = "HTML Report"
            elif ext == 'pdf':
                icon = "📕"
                type_label = "PDF Document"
            else:
                icon = "📁"
                type_label = "File"
            
            items += f"""
            <div class="file-item">
                <div class="file-icon">{icon}</div>
                <div class="file-info">
                    <div class="file-name">{name}</div>
                    <div class="file-type">{type_label}</div>
                </div>
                <a href="/download/{name}" class="download-btn">📥 Download</a>
            </div>"""
    else:
        items = """
        <div class="no-files">
            <div class="no-files-icon">📂</div>
            <div class="no-files-text">
                <h3>No Reports Generated Yet</h3>
                <p>Run the Azure Resource Inventory to generate reports and analysis files.</p>
                <a href="/cli-device-login" class="run-inventory-btn">🚀 Run Inventory Now</a>
            </div>
        </div>"""
    
    html = f"""
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Generated Reports - Azure Resource Inventory</title>
    <style>
      body {{ 
        font-family: system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; 
        margin: 0; 
        padding: 40px; 
        background: linear-gradient(135deg, #1e3c72 0%, #2a5298 50%, #0ea5e9 100%);
        min-height: 100vh;
      }}
      .container {{ 
        max-width: 800px; 
        margin: 0 auto; 
        background: white; 
        border-radius: 16px; 
        box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);
        overflow: hidden;
      }}
      .header {{ 
        background: linear-gradient(135deg, #0078d4 0%, #106ebe 100%); 
        color: white; 
        padding: 40px; 
        text-align: center; 
      }}
      .header h1 {{ 
        margin: 0; 
        font-size: 2.2rem; 
        font-weight: 700; 
        text-shadow: 0 2px 4px rgba(0,0,0,0.3); 
      }}
      .header p {{ 
        margin: 10px 0 0 0; 
        font-size: 1.1rem; 
        opacity: 0.9; 
      }}
      .content {{ padding: 30px; }}
      .file-grid {{ 
        display: flex; 
        flex-direction: column; 
        gap: 15px; 
      }}
      .file-item {{
        display: flex;
        align-items: center;
        background: #f8f9fa;
        padding: 20px;
        border-radius: 12px;
        border: 2px solid #e9ecef;
        transition: all 0.3s ease;
        box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
      }}
      .file-item:hover {{
        border-color: #0078d4;
        transform: translateY(-2px);
        box-shadow: 0 8px 15px rgba(0, 0, 0, 0.1);
      }}
      .file-icon {{
        font-size: 2.5rem;
        margin-right: 20px;
        min-width: 60px;
        text-align: center;
      }}
      .file-info {{
        flex: 1;
      }}
      .file-name {{
        font-size: 1.1rem;
        font-weight: 600;
        color: #1e293b;
        margin-bottom: 4px;
      }}
      .file-type {{
        font-size: 0.9rem;
        color: #64748b;
        font-weight: 500;
      }}
      .download-btn {{
        background: linear-gradient(135deg, #10b981 0%, #059669 100%);
        color: white;
        padding: 10px 20px;
        border-radius: 8px;
        text-decoration: none;
        font-weight: 600;
        font-size: 0.9rem;
        transition: all 0.3s ease;
        box-shadow: 0 4px 6px rgba(16, 185, 129, 0.3);
      }}
      .download-btn:hover {{
        transform: translateY(-1px);
        box-shadow: 0 6px 12px rgba(16, 185, 129, 0.4);
      }}
      .no-files {{
        text-align: center;
        padding: 60px 20px;
        background: #f8f9fa;
        border-radius: 12px;
        border: 2px dashed #d1d5db;
      }}
      .no-files-icon {{
        font-size: 4rem;
        margin-bottom: 20px;
        opacity: 0.6;
      }}
      .no-files-text h3 {{
        margin: 0 0 10px 0;
        color: #374151;
        font-size: 1.4rem;
      }}
      .no-files-text p {{
        margin: 0 0 25px 0;
        color: #6b7280;
        font-size: 1rem;
        line-height: 1.5;
      }}
      .run-inventory-btn {{
        display: inline-block;
        background: linear-gradient(135deg, #dc2626 0%, #991b1b 100%);
        color: white;
        padding: 15px 30px;
        border-radius: 10px;
        text-decoration: none;
        font-weight: 700;
        font-size: 1rem;
        transition: all 0.3s ease;
        box-shadow: 0 8px 12px rgba(220, 38, 38, 0.3);
      }}
      .run-inventory-btn:hover {{
        transform: translateY(-2px);
        box-shadow: 0 12px 18px rgba(220, 38, 38, 0.4);
      }}
      .back-link {{
        text-align: center;
        margin-top: 30px;
        padding-top: 20px;
        border-top: 1px solid #e5e7eb;
      }}
      .back-link a {{
        color: #0078d4;
        text-decoration: none;
        font-weight: 600;
        font-size: 1rem;
        display: inline-flex;
        align-items: center;
        gap: 8px;
        transition: all 0.2s ease;
      }}
      .back-link a:hover {{
        color: #106ebe;
        transform: translateX(-2px);
      }}
      .stats {{
        background: #e0f2fe;
        padding: 15px 20px;
        border-radius: 8px;
        margin-bottom: 20px;
        border-left: 4px solid #0078d4;
      }}
      .stats-text {{
        color: #0c4a6e;
        font-weight: 600;
        font-size: 0.95rem;
      }}
    </style>
  </head>
  <body>
    <div class="container">
      <div class="header">
        <h1>📊 Generated Reports</h1>
        <p>Azure Resource Inventory Analysis Results</p>
      </div>
      
      <div class="content">
        {f'<div class="stats"><div class="stats-text">📁 Found {len(files)} report file(s) ready for download</div></div>' if files else ''}
        
        <div class="file-grid">
          {items}
        </div>
        
        <div class="back-link">
          <a href="/">← Back to Main Dashboard</a>
        </div>
      </div>
    </div>
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
    
    # Check for the full device login message that contains both URL and code
    if "To sign in, use a web browser to open the page" in line and "https://microsoft.com/devicelogin" in line:
        # Extract the device code from the line (format: various patterns like FAZ9X9YTW)
        code_match = re.search(r'enter the code ([A-Z0-9]{6,12}) to authenticate', line)
        url = "https://microsoft.com/devicelogin"
        
        if code_match:
            code = code_match.group(1)
            enhanced = f'''<div style="background: #e3f2fd; padding: 15px; border-radius: 10px; margin: 10px 0; border: 2px solid #2196f3; max-width: 600px; margin-left: auto; margin-right: auto;">
                <div style="text-align: center; margin-bottom: 15px;">
                    <strong style="color: #1976d2; font-size: 16px;">🌐 Azure Device Authentication Required</strong>
                </div>
                
                <div style="background: #e8f5e8; padding: 15px; border-radius: 6px; margin: 10px 0; text-align: center;">
                    <strong style="color: #2e7d32; display: block; margin-bottom: 8px;">🔗 Step 1: Click to open login page</strong>
                    <a href="{url}" target="_blank" style="display: inline-block; background: #4caf50; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; font-weight: bold; font-size: 14px; margin: 3px;">{url}</a>
                </div>
                
                <div style="background: #fff3cd; padding: 5px; border-radius: 6px; margin: 10px 0; text-align: center;">
                    <strong style="color: #856404; display: block; margin-bottom: 8px;">🔑 Step 2: Enter this code</strong>
                    <div style="background: #ffeb3b; padding: 8px 15px; font-size: 24px; font-weight: bold; border-radius: 6px; color: #f57f17; font-family: monospace; letter-spacing: 2px; margin: 5px 0; display: inline-block;">{code}</div>
                    <br>
                    <button onclick="navigator.clipboard.writeText('{code}'); this.innerHTML='✅ Copied!'; setTimeout(() => this.innerHTML='📋 Copy Code', 2000);" style="margin-top: 8px; background: #2196f3; color: white; border: none; padding: 10px 20px; border-radius: 6px; cursor: pointer; font-weight: bold; font-size: 13px;">📋 Copy Code</button>
                </div>
            </div>'''
        else:
            enhanced = f'<div style="background: #e3f2fd; padding: 15px; border-radius: 8px; margin: 10px 0;"><strong style="color: #1976d2;">🌐 {line.strip()}</strong></div>'
    elif "https://microsoft.com/devicelogin" in line and "To sign in" not in line:
        # Standalone URL
        url = "https://microsoft.com/devicelogin"
        enhanced = f'<div style="background: #e8f5e8; padding: 20px; border-radius: 8px; margin: 15px 0; text-align: center;"><strong style="color: #2e7d32; display: block; margin-bottom: 10px;">🔗 Click to open login page:</strong><a href="{url}" target="_blank" style="display: inline-block; background: #4caf50; color: white; padding: 15px 30px; text-decoration: none; border-radius: 8px; font-weight: bold;">{url}</a></div>'
    elif re.search(r'\b[A-Z0-9]{6,12}\b', line) and ("code" in line.lower() or "enter" in line.lower()):
        # Standalone device code
        match = re.search(r'\b([A-Z0-9]{6,12})\b', line)
        if match:
            code = match.group(1)
            enhanced = f'<div style="background: #fff3cd; padding: 20px; border-radius: 8px; margin: 15px 0; text-align: center;"><strong style="color: #856404; display: block; margin-bottom: 10px;">🔑 Your Device Code:</strong><span style="background: #ffeb3b; padding: 10px 20px; font-size: 24px; font-weight: bold; border-radius: 6px; color: #f57f17; font-family: monospace; letter-spacing: 2px;">{code}</span><br><button onclick="navigator.clipboard.writeText(\'{code}\'); this.innerHTML=\'✅ Copied!\'; setTimeout(() => this.innerHTML=\'📋 Copy Code\', 2000);" style="margin-top: 10px; background: #2196f3; color: white; border: none; padding: 10px 20px; border-radius: 6px; cursor: pointer;">📋 Copy Code</button></div>'
        else:
            enhanced = line + "<br>"
    elif "Continuing will" in line or "complete the authentication" in line:
        enhanced = f'<div style="background: #f3e5f5; padding: 12px; border-radius: 6px; margin: 8px 0;"><em style="color: #7b1fa2;">ℹ️ {line.strip()}</em></div>'
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
      body { 
        font-family: system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; 
        margin: 0; 
        padding: 40px; 
        background: linear-gradient(135deg, #1e3c72 0%, #2a5298 50%, #0ea5e9 100%);
        min-height: 100vh;
      }
      .container { 
        max-width: 700px; 
        margin: 0 auto; 
        background: white; 
        border-radius: 16px; 
        box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);
        overflow: hidden;
      }
      .header { 
        background: linear-gradient(135deg, #0078d4 0%, #106ebe 100%); 
        color: white; 
        padding: 25px; 
        text-align: center; 
      }
      .header h1 { 
        margin: 0; 
        font-size: 2rem; 
        font-weight: 700; 
        text-shadow: 0 2px 4px rgba(0,0,0,0.3); 
      }
      .header p { 
        margin: 8px 0 0 0; 
        font-size: 1rem; 
        opacity: 0.9; 
      }
      .content { padding: 25px; }
      .warning { 
        background: #f0f9ff; 
        padding: 15px; 
        border-radius: 8px; 
        margin-bottom: 20px; 
        border-left: 4px solid #0078d4; 
        font-size: 0.9rem;
      }
      .warning strong { 
        color: #dc2626; 
        font-weight: bold;
        font-size: 1.1em;
      }
      .form-group { margin-bottom: 18px; }
      label { 
        display: block; 
        margin-bottom: 8px; 
        font-weight: 600; 
        color: #1e293b;
      }
      input { 
        width: 100%; 
        padding: 15px 20px; 
        border: 2px solid #e2e8f0; 
        border-radius: 12px; 
        font-size: 1.1rem;
        font-weight: 500;
        text-align: center;
        background: #f8f9fa;
        transition: all 0.3s ease;
        box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
      }
      input:focus { 
        outline: none;
        border-color: #0078d4;
        background: #ffffff;
        box-shadow: 0 0 0 3px rgba(0, 120, 212, 0.15), 0 4px 8px rgba(0, 0, 0, 0.1);
        transform: translateY(-1px);
      }
      input::placeholder {
        color: #9ca3af;
        font-style: italic;
        font-weight: 400;
      }
      .run-button { 
        display: inline-block; 
        background: linear-gradient(135deg, #dc2626 0%, #991b1b 100%); 
        color: white; 
        padding: 12px 24px; 
        font-size: 1rem; 
        font-weight: 700; 
        border: none; 
        border-radius: 8px; 
        cursor: pointer; 
        text-decoration: none; 
        box-shadow: 0 8px 12px -3px rgba(220, 38, 38, 0.3), 0 4px 6px -2px rgba(220, 38, 38, 0.05);
        transition: all 0.3s ease;
        text-transform: uppercase;
        letter-spacing: 1px;
      }
      .run-button:hover { 
        transform: translateY(-2px); 
        box-shadow: 0 15px 25px -5px rgba(220, 38, 38, 0.4), 0 10px 10px -5px rgba(220, 38, 38, 0.1);
      }
      .back-link { 
        margin-top: 20px; 
        text-align: center;
      }
      .back-link a {
        color: #0078d4;
        text-decoration: none;
        font-weight: 500;
      }
      .back-link a:hover {
        text-decoration: underline;
      }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="header">
        <h1>Device Authentication</h1>
        <p>Secure Azure CLI Login for Resource Inventory</p>
      </div>
      
      <div class="content">
        <div class="warning">
          <strong>🔒 Secure Authentication:</strong> Uses Azure CLI device login for secure authentication.
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
          
          <div style="text-align: center;">
            <button type="submit" class="run-button">Start Authentication</button>
          </div>
          
          <div class="back-link">
            <a href="/">← Back to Main Page</a>
          </div>
        </form>
      </div>
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
      body { 
        font-family: system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; 
        margin: 0; 
        padding: 15px; 
        background: linear-gradient(135deg, #1e3c72 0%, #2a5298 50%, #0ea5e9 100%);
        min-height: 100vh;
      }
      .container { 
        max-width: 600px; 
        margin: 0 auto; 
        background: white; 
        border-radius: 10px; 
        box-shadow: 0 15px 20px -5px rgba(0, 0, 0, 0.1), 0 8px 8px -5px rgba(0, 0, 0, 0.04);
        overflow: hidden;
        min-height: 90vh;
      }
      .header { 
        background: linear-gradient(135deg, #0078d4 0%, #106ebe 100%); 
        color: white; 
        padding: 12px; 
        text-align: center; 
      }
      .header h1 { 
        margin: 0; 
        font-size: 1.4rem; 
        font-weight: 700; 
        text-shadow: 0 2px 4px rgba(0,0,0,0.3); 
      }
      .header p { 
        margin: 3px 0 0 0; 
        font-size: 0.8rem; 
        opacity: 0.9; 
      }
      .content { padding: 15px; }
      .spinner { 
        display: inline-block; 
        width: 24px; 
        height: 24px; 
        border: 3px solid #e2e8f0; 
        border-top: 3px solid #0078d4; 
        border-radius: 50%; 
        animation: spin 1s linear infinite; 
        margin-right: 12px; 
      }
      @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
      .status {
        background: #f0f9ff;
        padding: 12px 15px;
        border-radius: 8px;
        margin-bottom: 12px;
        border-left: 4px solid #0078d4;
        font-size: 1rem;
        font-weight: 600;
        transition: all 0.3s ease;
        box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
      }
      .status.processing {
        background: #fff7ed;
        border-left-color: #f59e0b;
        color: #92400e;
      }
      .status.completed {
        background: #f0fdf4;
        border-left-color: #10b981;
        color: #065f46;
      }
      .output { 
        background: #1e293b; 
        color: #e2e8f0; 
        padding: 12px; 
        border-radius: 6px; 
        font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace; 
        white-space: pre-wrap; 
        height: 600px; 
        overflow-y: auto; 
        margin-top: 8px;
        box-shadow: inset 0 2px 4px rgba(0, 0, 0, 0.1);
        font-size: 0.75rem;
        line-height: 1.2;
      }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="header">
        <h1>Azure CLI Device Login</h1>
        <p>Authentication & Resource Inventory in Progress</p>
      </div>
      
      <div class="content">
        <div class="status">
          <span class="spinner"></span>
          Running Azure CLI device login... Watch for authentication instructions!
        </div>
        <div id="output" class="output"></div>
        
        <div id="manual-nav" style="display: none; text-align: center; margin-top: 20px; padding: 15px; border-radius: 8px;">
          <!-- Content will be dynamically populated based on success/failure -->
        </div>
      
      <script>
        const jobId = ''' + f"'{job_id}'" + ''';
        let checkCount = 0;
        const maxChecks = 900; // 30 minutes (900 * 2 seconds) - ARI can take a long time
        let lastOutputLength = 0;
        let processingStartTime = null;
        
        function checkOutput() {
          checkCount++;
          fetch(`/job-status/${jobId}`)
            .then(response => response.json())
            .then(data => {
              console.log('Job status:', data.status, 'Check:', checkCount);
              const outputElement = document.getElementById('output');
              const currentOutput = data.output || '';
              outputElement.innerHTML = currentOutput;
              outputElement.scrollTop = outputElement.scrollHeight;
              
              // Track output changes for heartbeat
              const currentOutputLength = currentOutput.length;
              if (currentOutputLength > lastOutputLength) {
                lastOutputLength = currentOutputLength;
              }
              
              // Update status message based on progress
              const statusElement = document.querySelector('.status');
              const output = data.output || '';
              
              if (output.includes('Azure Resource Inventory execution') || 
                  output.includes('Starting Invoke-ARI') || 
                  output.includes('Connected to Azure successfully') ||
                  output.includes('Attempting ARI execution') ||
                  output.includes('Gathering VM Extra Details') ||
                  output.includes('Running API Inventory')) {
                statusElement.className = 'status processing';
                
                // Track when processing started
                if (!processingStartTime) {
                  processingStartTime = Date.now();
                }
                
                // Calculate elapsed time
                const elapsed = Math.floor((Date.now() - processingStartTime) / 1000);
                const minutes = Math.floor(elapsed / 60);
                const seconds = elapsed % 60;
                
                // Show progress based on what's happening
                let progressMsg = '🔍 Processing Azure Resource Inventory';
                if (output.includes('Running API Inventory')) {
                  progressMsg = '📊 Scanning Azure resources and generating reports';
                } else if (output.includes('Gathering VM Extra Details')) {
                  progressMsg = '🖥️ Gathering detailed VM information';
                } else if (output.includes('Extracting Subscriptions')) {
                  progressMsg = '📋 Extracting subscription details';
                }
                
                // Add heartbeat indicator if no output for a while
                let heartbeat = '';
                if (currentOutputLength === lastOutputLength && checkCount > 10) {
                  const dots = '.'.repeat((checkCount % 4) + 1);
                  heartbeat = ` <span style="color: #10b981;">Processing${dots}</span>`;
                }
                
                statusElement.innerHTML = `<span class="spinner"></span>${progressMsg}...${heartbeat} <br><small style="opacity: 0.7;">Running for ${minutes}m ${seconds}s - Large environments may take 10-30 minutes</small>`;
              } else if (output.includes('completed successfully') || data.status === 'completed') {
                statusElement.className = 'status completed';
                statusElement.innerHTML = '✅ Azure Resource Inventory completed successfully!';
              } else if (output.includes('Failed to resolve tenant') || 
                        output.includes('ERROR: Failed to resolve') ||
                        output.includes('Process failed with exit code')) {
                statusElement.className = 'status';
                statusElement.style.background = '#fef2f2';
                statusElement.style.borderLeftColor = '#ef4444';
                statusElement.style.color = '#991b1b';
                statusElement.innerHTML = '❌ Authentication failed - Please check your Azure permissions and try again.';
              } else if (output.includes('Authentication completed') || 
                        output.includes('Verifying authentication') ||
                        output.includes('Current Subscription:') ||
                        output.includes('Already authenticated')) {
                statusElement.className = 'status processing';
                statusElement.innerHTML = '<span class="spinner"></span>🔐 Authentication successful! Initializing Azure Resource Inventory...';
              }
              
              if (data.status === 'completed') {
                clearInterval(interval);
                console.log('Job completed, redirecting to outputs...');
                setTimeout(() => {
                  window.location.href = '/outputs';
                }, 2000);
              } else if (data.status === 'failed' || checkCount >= maxChecks) {
                clearInterval(interval);
                const spinner = document.querySelector('.spinner');
                if (spinner) spinner.style.display = 'none';
                
                // Add a delay before checking files to ensure they're fully written
                setTimeout(() => {
                  // Check if any reports were generated before showing navigation
                  fetch('/debug-files')
                    .then(response => response.text())
                    .then(debugData => {
                      console.log('Debug data:', debugData);
                      const hasFiles = debugData.includes('"filtered_files": [') && !debugData.includes('"filtered_files": []');
                      
                      if (hasFiles) {
                        // Show success navigation if files exist
                        document.getElementById('manual-nav').innerHTML = `
                          <p style="margin: 0 0 10px 0; color: #2e7d32; font-weight: 500;">🎉 Reports generated successfully!</p>
                          <a href="/outputs" style="display: inline-block; background: #4caf50; color: white; padding: 10px 20px; text-decoration: none; border-radius: 6px; font-weight: bold;">📁 View Generated Reports</a>
                          <span style="margin: 0 10px;">|</span>
                          <a href="/" style="display: inline-block; background: #2196f3; color: white; padding: 10px 20px; text-decoration: none; border-radius: 6px; font-weight: bold;">🏠 Back to Home</a>
                        `;
                        document.getElementById('manual-nav').style.display = 'block';
                      } else {
                        // Show error navigation if no files exist
                        document.getElementById('manual-nav').innerHTML = `
                          <p style="margin: 0 0 10px 0; color: #d32f2f; font-weight: 500;">❌ Process failed - No reports were generated</p>
                          <a href="/cli-device-login" style="display: inline-block; background: #dc2626; color: white; padding: 10px 20px; text-decoration: none; border-radius: 6px; font-weight: bold;">🔄 Try Again</a>
                          <span style="margin: 0 10px;">|</span>
                          <a href="/" style="display: inline-block; background: #2196f3; color: white; padding: 10px 20px; text-decoration: none; border-radius: 6px; font-weight: bold;">🏠 Back to Home</a>
                        `;
                        document.getElementById('manual-nav').style.display = 'block';
                      }
                    })
                    .catch(error => {
                      console.error('Error checking files:', error);
                      // Fallback: just show home button
                      document.getElementById('manual-nav').innerHTML = `
                        <p style="margin: 0 0 10px 0; color: #d32f2f; font-weight: 500;">❌ Process encountered errors</p>
                        <a href="/cli-device-login" style="display: inline-block; background: #dc2626; color: white; padding: 10px 20px; text-decoration: none; border-radius: 6px; font-weight: bold;">🔄 Try Again</a>
                        <span style="margin: 0 10px;">|</span>
                        <a href="/" style="display: inline-block; background: #2196f3; color: white; padding: 10px 20px; text-decoration: none; border-radius: 6px; font-weight: bold;">🏠 Back to Home</a>
                      `;
                      document.getElementById('manual-nav').style.display = 'block';
                    });
                }, 3000); // Wait 3 seconds for files to be fully written
              }
            })
            .catch(error => {
              console.error('Error checking job status:', error);
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
    """Generate bash script using Azure CLI for device login and ARI execution"""
    script_parts = [
        "#!/bin/bash",
        "set -e",
        f"OUT_DIR='{output_dir}'",
        "mkdir -p \"$OUT_DIR\"",
        "",
        "echo '🔧 AZURE CLI DEVICE LOGIN & ARI EXECUTION'",
        "echo '======================================='",
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
        "ACCOUNT_INFO=$(az account show)",
        "echo \"$ACCOUNT_INFO\"",
        "",
        "# Extract subscription and tenant info for PowerShell",
        "CURRENT_SUBSCRIPTION=$(echo \"$ACCOUNT_INFO\" | jq -r '.id // empty')",
        "CURRENT_TENANT=$(echo \"$ACCOUNT_INFO\" | jq -r '.tenantId // empty')",
        "",
        "echo '✅ Azure CLI authentication completed!'",
        "echo \"📋 Current Subscription: $CURRENT_SUBSCRIPTION\"",
        "echo \"🏢 Current Tenant: $CURRENT_TENANT\"",
        "",
        "echo 'Starting Azure Resource Inventory execution...'",
        "echo '================================================='",
        "",
        "# Create PowerShell script file with robust error handling",
        "cat > /tmp/run_ari.ps1 << 'EOF'",
        "$ErrorActionPreference = 'Stop'",
        "",
        "Write-Host 'Setting up Azure Resource Inventory module...' -ForegroundColor Green",
        "try {",
        "    # Check if module exists in current directory first",
        "    if (Test-Path './AzureResourceInventory.psm1') {",
        "        Import-Module './AzureResourceInventory.psm1' -Force -ErrorAction Stop",
        "        Write-Host 'Local module imported successfully!' -ForegroundColor Green",
        "    } elseif (Get-Module -ListAvailable -Name AzureResourceInventory) {",
        "        Import-Module AzureResourceInventory -Force -ErrorAction Stop",
        "        Write-Host 'Installed module imported successfully!' -ForegroundColor Green",
        "    } else {",
        "        Write-Host 'Installing AzureResourceInventory from PowerShell Gallery...' -ForegroundColor Yellow",
        "        Install-Module -Name AzureResourceInventory -Force -Scope CurrentUser -ErrorAction Stop",
        "        Import-Module AzureResourceInventory -Force -ErrorAction Stop",
        "        Write-Host 'Module installed and imported successfully!' -ForegroundColor Green",
        "    }",
        "} catch {",
        "    Write-Error \"Failed to setup AzureResourceInventory module: $($_.Exception.Message)\"",
        "    Write-Host 'Trying alternative approach...' -ForegroundColor Yellow",
        "    try {",
        "        # Fallback: try to run without explicit module import",
        "        Write-Host 'Attempting direct execution...' -ForegroundColor Cyan",
        "    } catch {",
        "        Write-Error 'All module setup attempts failed'",
        "        exit 1",
        "    }",
        "}",
        "",
        "Write-Host 'Connecting to Azure using available credentials...' -ForegroundColor Green",
        "try {",
        "    # Check if managed identity is available first",
        "    $useManagedIdentity = $env:USE_MANAGED_IDENTITY -eq 'true' -or $env:AZURE_CLIENT_ID -eq 'MSI'",
        "    ",
        "    if ($useManagedIdentity) {",
        "        Write-Host 'Using Managed Identity authentication...' -ForegroundColor Cyan",
        "        try {",
        "            Connect-AzAccount -Identity -ErrorAction Stop",
        "            Write-Host '✅ Connected using Managed Identity!' -ForegroundColor Green",
        "            $context = Get-AzContext",
        "            Write-Host \"Tenant ID: $($context.Tenant.Id)\" -ForegroundColor Cyan",
        "            Write-Host \"Subscription ID: $($context.Subscription.Id)\" -ForegroundColor Cyan",
        "            Write-Host \"Account: $($context.Account.Id)\" -ForegroundColor Cyan",
        "        } catch {",
        "            Write-Host \"Managed Identity failed: $($_.Exception.Message)\" -ForegroundColor Yellow",
        "            Write-Host 'Falling back to Azure CLI credentials...' -ForegroundColor Yellow",
        "            $useManagedIdentity = $false",
        "        }",
        "    }",
        "    ",
        "    if (-not $useManagedIdentity) {",
        "        Write-Host 'Using Azure CLI credentials...' -ForegroundColor Cyan",
        "        # Import Azure CLI credentials into PowerShell",
        "        $azContext = az account show --output json | ConvertFrom-Json",
        "    if ($azContext) {",
        "        Write-Host \"Found Azure CLI context for: $($azContext.name)\" -ForegroundColor Green",
        "        Write-Host \"Tenant ID: $($azContext.tenantId)\" -ForegroundColor Cyan",
        "        Write-Host \"Subscription ID: $($azContext.id)\" -ForegroundColor Cyan",
        "        Write-Host \"Account: $($azContext.user.name)\" -ForegroundColor Cyan",
        "        ",
        "        # Get access token with tenant specification",
        "        Write-Host 'Getting access token...' -ForegroundColor Yellow",
        "        $accessToken = az account get-access-token --tenant $azContext.tenantId --query accessToken --output tsv",
        "        if (-not $accessToken) {",
        "            throw 'Failed to get access token from Azure CLI'",
        "        }",
        "        ",
        "        # Try multiple connection methods",
        "        Write-Host 'Attempting PowerShell connection (Method 1: Full parameters)...' -ForegroundColor Yellow",
        "        try {",
        "            Connect-AzAccount -AccessToken $accessToken -AccountId $azContext.user.name -TenantId $azContext.tenantId -ErrorAction Stop",
        "            Write-Host 'Connected to Azure successfully using CLI credentials!' -ForegroundColor Green",
        "        } catch {",
        "            Write-Host \"Method 1 failed: $($_.Exception.Message)\" -ForegroundColor Yellow",
        "            Write-Host 'Attempting PowerShell connection (Method 2: Simplified)...' -ForegroundColor Yellow",
        "            try {",
        "                # Try without AccountId in case that's causing issues",
        "                Connect-AzAccount -AccessToken $accessToken -TenantId $azContext.tenantId -ErrorAction Stop",
        "                Write-Host 'Connected to Azure successfully (Method 2)!' -ForegroundColor Green",
        "            } catch {",
        "                Write-Host \"Method 2 failed: $($_.Exception.Message)\" -ForegroundColor Yellow",
        "                Write-Host 'Attempting PowerShell connection (Method 3: Device login fallback)...' -ForegroundColor Yellow",
        "                # As last resort, try device login directly in PowerShell",
        "                Connect-AzAccount -UseDeviceAuthentication -TenantId $azContext.tenantId -ErrorAction Stop",
        "                Write-Host 'Connected using device authentication!' -ForegroundColor Green",
        "            }",
        "        }",
        "    } else {",
        "        throw 'No Azure CLI context found'",
        "    }",
        "    }",
        "} catch {",
        "    Write-Error \"Failed to connect to Azure: $($_.Exception.Message)\"",
        "    Write-Host 'Debug information:' -ForegroundColor Yellow",
        "    Write-Host \"Current working directory: $(Get-Location)\" -ForegroundColor Gray",
        "    Write-Host \"PowerShell version: $($PSVersionTable.PSVersion)\" -ForegroundColor Gray",
        "    Write-Host \"Available Az modules:\" -ForegroundColor Gray",
        "    Get-Module Az* -ListAvailable | Select-Object Name, Version | Format-Table -AutoSize",
        "    exit 1",
        "}"
    ])
    
    # Add subscription setting if specified
    if subscription:
        script_parts.extend([
            "",
            "Write-Host 'Setting subscription context...' -ForegroundColor Yellow",
            "try {",
            f"    Set-AzContext -SubscriptionId '{subscription}' -ErrorAction Stop",
            "    Write-Host 'Subscription context set successfully!' -ForegroundColor Green",
            "} catch {",
            "    Write-Error 'Failed to set subscription context: $_'",
            "    exit 1",
            "}"
        ])
    
    # Add the ARI execution with better error handling
    script_parts.extend([
        "",
        f"$reportDir = '{output_dir}'",
        "$reportName = 'AzureResourceInventory_' + (Get-Date -Format 'yyyyMMdd_HHmmss')",
        "",
        "Write-Host 'Creating output directory...' -ForegroundColor Yellow",
        "New-Item -Path $reportDir -ItemType Directory -Force | Out-Null",
        "",
        "Write-Host 'Starting Invoke-ARI execution...' -ForegroundColor Yellow",
        "Write-Host \"Report Directory: $reportDir\" -ForegroundColor Cyan",
        "Write-Host \"Report Name: $reportName\" -ForegroundColor Cyan",
        "",
        "try {",
        "    # Get current tenant and subscription info",
        "    $context = Get-AzContext -ErrorAction SilentlyContinue",
        "    if ($context) {",
        "        $tenantId = $context.Tenant.Id",
        "        $subscriptionId = $context.Subscription.Id",
        "        Write-Host \"Using PowerShell context - Tenant: $tenantId\" -ForegroundColor Cyan",
        "        Write-Host \"Using PowerShell context - Subscription: $subscriptionId\" -ForegroundColor Cyan",
        "    } else {",
        "        Write-Host 'No PowerShell context found, using Azure CLI context...' -ForegroundColor Yellow",
        "        $cliContext = az account show --output json | ConvertFrom-Json",
        "        $tenantId = $cliContext.tenantId",
        "        $subscriptionId = $cliContext.id",
        "        Write-Host \"Using CLI context - Tenant: $tenantId\" -ForegroundColor Cyan",
        "        Write-Host \"Using CLI context - Subscription: $subscriptionId\" -ForegroundColor Cyan",
        "    }",
        "    ",
        "    # Use simple string-based execution to avoid PowerShell object casting issues",
        "    Write-Host 'Starting Azure Resource Inventory execution...' -ForegroundColor Yellow",
        "    Write-Host \"Report Directory: $reportDir\" -ForegroundColor Cyan",
        "    Write-Host \"Report Name: $reportName\" -ForegroundColor Cyan",
        "    Write-Host \"Tenant ID: $tenantId\" -ForegroundColor Cyan", 
        "    Write-Host \"Subscription ID: $subscriptionId\" -ForegroundColor Cyan",
        "    Write-Host ''",
        "    ",
        "    # Method 1: Try with string-based parameter construction",
        "    Write-Host 'Attempting ARI execution (Method 1: String Parameters)...' -ForegroundColor Green",
        "    $paramString = \"-ReportDir '$reportDir' -ReportName '$reportName' -TenantID '$tenantId' -SubscriptionID '$subscriptionId' -SkipDiagram\"",
        "    Write-Host \"Parameters: $paramString\" -ForegroundColor Gray",
        "    ",
        "    $expression = \"Invoke-ARI $paramString\"",
        "    Write-Host \"Executing: $expression\" -ForegroundColor Gray",
        "    Write-Host ''",
        "    Write-Host '⏳ Azure Resource Inventory is now running...' -ForegroundColor Yellow",
        "    Write-Host 'This process scans all resources in your subscription and may take 10-30 minutes.' -ForegroundColor Yellow",
        "    Write-Host 'The screen may appear quiet while ARI works - this is normal.' -ForegroundColor Yellow",
        "    Write-Host 'Please be patient while we analyze your Azure environment.' -ForegroundColor Yellow",
        "    Write-Host ''",
        "    ",
        "    # Execute ARI with progress tracking",
        "    $startTime = Get-Date",
        "    Invoke-Expression $expression",
        "    $endTime = Get-Date",
        "    $duration = $endTime - $startTime",
        "    Write-Host \"\\n✅ ARI execution completed in $($duration.TotalMinutes.ToString('0.0')) minutes!\" -ForegroundColor Green",
        "    ",
        "    Write-Host 'Azure Resource Inventory completed successfully!' -ForegroundColor Green",
        "} catch {",
        "    Write-Host \"Method 1 failed: $($_.Exception.Message)\" -ForegroundColor Red",
        "    ",
        "    # Method 2: Try with minimal parameters",
        "    Write-Host 'Attempting ARI execution (Method 2: Minimal Parameters)...' -ForegroundColor Yellow",
        "    try {",
        "        $minimalExpression = \"Invoke-ARI -ReportDir '$reportDir' -SkipDiagram\"",
        "        Write-Host \"Minimal Command: $minimalExpression\" -ForegroundColor Gray",
        "        Invoke-Expression $minimalExpression",
        "        Write-Host 'Minimal execution completed!' -ForegroundColor Green",
        "    } catch {",
        "        Write-Host \"Method 2 failed: $($_.Exception.Message)\" -ForegroundColor Red",
        "        ",
        "        # Method 3: Try direct cmdlet call",
        "        Write-Host 'Attempting ARI execution (Method 3: Direct Call)...' -ForegroundColor Yellow",
        "        try {",
        "            & 'Invoke-ARI' -ReportDir $reportDir",
        "            Write-Host 'Direct execution completed!' -ForegroundColor Green",
        "        } catch {",
        "            Write-Error \"All execution methods failed: $($_.Exception.Message)\"",
        "            exit 1",
        "        }",
        "    }",
        "}",
        "",
        "# Check for generated files with enhanced debugging",
        "Write-Host 'Checking for generated files...' -ForegroundColor Green",
        "Write-Host \"Report Directory: $reportDir\" -ForegroundColor Cyan",
        "Write-Host \"Directory exists: $(Test-Path $reportDir)\" -ForegroundColor Cyan",
        "if (Test-Path $reportDir) {",
        "    $allFiles = Get-ChildItem -Path $reportDir -ErrorAction SilentlyContinue",
        "    $files = $allFiles | Where-Object { -not $_.PSIsContainer }",
        "    Write-Host \"Total items in directory: $($allFiles.Count)\" -ForegroundColor Cyan",
        "    Write-Host \"Files in directory: $($files.Count)\" -ForegroundColor Cyan",
        "    if ($files) {",
        "        Write-Host 'Generated files:' -ForegroundColor Green",
        "        $files | Select-Object Name, @{Name='Size(MB)';Expression={[math]::Round($_.Length/1MB,2)}}, LastWriteTime | Format-Table -AutoSize",
        "        Write-Host 'File paths:' -ForegroundColor Yellow",
        "        $files | ForEach-Object { Write-Host \"  - $($_.FullName)\" -ForegroundColor Gray }",
        "    } else {",
        "        Write-Warning 'No files found in output directory'",
        "        Write-Host 'Directory contents:' -ForegroundColor Yellow",
        "        $allFiles | ForEach-Object { Write-Host \"  - $($_.Name) (Type: $($_.GetType().Name))\" -ForegroundColor Gray }",
        "    }",
        "} else {",
        "    Write-Warning 'Output directory not found!'",
        "    Write-Host \"Attempting to create directory: $reportDir\" -ForegroundColor Yellow",
        "    try {",
        "        New-Item -Path $reportDir -ItemType Directory -Force",
        "        Write-Host 'Directory created successfully' -ForegroundColor Green",
        "    } catch {",
        "        Write-Error \"Failed to create directory: $_\"",
        "    }",
        "}",
        "EOF",
        "",
        "# Execute the PowerShell script with verbose output",
        "echo 'Executing PowerShell script...'",
        "pwsh -NoProfile -ExecutionPolicy Bypass -File /tmp/run_ari.ps1",
        "",
        "echo 'Process completed! Check the outputs directory for your reports.'"
    ])
    
    return "\n".join(script_parts)


def run_cli_job(job_id, script):
    """Run Azure CLI script with enhanced device code formatting"""
    try:
        print(f"[JOB {job_id}] Starting Azure CLI device login process...")
        jobs[job_id]['output'] += "Starting Azure CLI device login process...<br>"
        
        # Write script to file
        script_file = "/tmp/cli_device_login.sh"
        with open(script_file, 'w') as f:
            f.write(script)
        os.chmod(script_file, 0o755)
        
        print(f"[JOB {job_id}] Script written to {script_file}, starting execution...")
        
        # Run the script
        process = subprocess.Popen(
            ["/bin/bash", script_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )
        
        jobs[job_id]['process'] = process
        
        print(f"[JOB {job_id}] Process started with PID: {process.pid}")
        
        # Stream output with enhanced formatting
        line_count = 0
        for line in iter(process.stdout.readline, ''):
            if line:
                line_count += 1
                # Print every line to container logs for debugging
                print(f"[JOB {job_id}] LINE {line_count}: {line.strip()}")
                
                # Enhance device code formatting
                enhanced_line = enhance_device_code_output(line)
                jobs[job_id]['output'] += enhanced_line
        
        process.wait()
        
        print(f"[JOB {job_id}] Process completed with exit code: {process.returncode}")
        print(f"[JOB {job_id}] Total lines captured: {line_count}")
        
        # Add a small delay to ensure files are fully written to disk
        # This prevents race condition where frontend checks before files are flushed
        time.sleep(2)
        
        if process.returncode == 0:
            print(f"[JOB {job_id}] SUCCESS: ARI execution completed successfully")
            jobs[job_id]['status'] = 'completed'
            jobs[job_id]['output'] += '''<br><div style="background: #d4edda; padding: 15px; border-radius: 8px; margin: 15px 0; border-left: 4px solid #28a745;">
                <strong style="color: #155724; font-size: 16px;">🎉 Azure Resource Inventory completed successfully!</strong><br>
                <span style="color: #155724;">Your reports have been generated and are ready for download.</span>
            </div>'''
        else:
            print(f"[JOB {job_id}] FAILED: Process failed with exit code {process.returncode}")
            jobs[job_id]['status'] = 'failed'
            jobs[job_id]['output'] += f'''<br><div style="background: #f8d7da; padding: 15px; border-radius: 8px; margin: 15px 0; border-left: 4px solid #dc3545;">
                <strong style="color: #721c24; font-size: 16px;">❌ Process failed with exit code {process.returncode}</strong><br>
                <span style="color: #721c24;">Please check the output above for error details.</span>
            </div>'''
            
    except Exception as e:
        print(f"[JOB {job_id}] EXCEPTION: {str(e)}")
        jobs[job_id]['status'] = 'failed'
        jobs[job_id]['output'] += f"<br>Error: {str(e)}"


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    app.run(host="0.0.0.0", port=port)