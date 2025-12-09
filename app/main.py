from flask import Flask, render_template_string, request, redirect, url_for, jsonify
import os
import subprocess
import shlex
import threading
import uuid
import time
from datetime import datetime
import re
import json
import pickle


app = Flask(__name__)

# Global jobs dictionary to track running processes
jobs = {}

# Job persistence directory - use same volume as ARI output for persistence
def get_jobs_dir():
    """Get the jobs directory, creating it if necessary"""
    output_dir = os.environ.get("ARI_OUTPUT_DIR", os.path.expanduser("~/AzureResourceInventory"))
    jobs_dir = os.path.join(output_dir, ".jobs")
    os.makedirs(jobs_dir, exist_ok=True)
    return jobs_dir

JOBS_DIR = get_jobs_dir()

def save_job(job_id, job_data):
    """Save job data to disk for persistence"""
    try:
        job_file = os.path.join(JOBS_DIR, f"{job_id}.json")
        # Convert datetime objects to strings for JSON serialization
        serializable_data = {
            'status': job_data.get('status'),
            'output': job_data.get('output', ''),
            'created_at': job_data.get('created_at').isoformat() if 'created_at' in job_data else None,
            'cleanup_status': job_data.get('cleanup_status', 'pending'),
            'cleanup_error': job_data.get('cleanup_error', '')
        }
        with open(job_file, 'w') as f:
            json.dump(serializable_data, f)
    except Exception as e:
        print(f"Error saving job {job_id}: {e}")

def load_job(job_id):
    """Load job data from disk"""
    try:
        job_file = os.path.join(JOBS_DIR, f"{job_id}.json")
        if os.path.exists(job_file):
            with open(job_file, 'r') as f:
                data = json.load(f)
                # Convert ISO format strings back to datetime
                if data.get('created_at'):
                    data['created_at'] = datetime.fromisoformat(data['created_at'])
                return data
    except Exception as e:
        print(f"Error loading job {job_id}: {e}")
    return None

def load_all_jobs():
    """Load all persisted jobs on startup"""
    try:
        print(f"Loading jobs from: {JOBS_DIR}")
        if not os.path.exists(JOBS_DIR):
            print(f"Jobs directory does not exist yet: {JOBS_DIR}")
            return
        
        job_files = [f for f in os.listdir(JOBS_DIR) if f.endswith('.json')]
        print(f"Found {len(job_files)} job files to restore")
        
        for filename in job_files:
            job_id = filename[:-5]  # Remove .json extension
            job_data = load_job(job_id)
            if job_data:
                jobs[job_id] = job_data
                print(f"Restored job: {job_id} with status: {job_data.get('status')}")
        
        print(f"Total jobs in memory after restore: {len(jobs)}")
    except Exception as e:
        print(f"Error loading jobs: {e}")
        import traceback
        print(traceback.format_exc())

# Load existing jobs on startup
print("=" * 50)
print("Flask app starting - loading persisted jobs...")
load_all_jobs()
print("=" * 50)


INDEX_HTML = """
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>☁️</text></svg>">
    <title>Azure Inventory</title>
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

@app.route("/check-jobs", methods=["GET"])
def check_jobs():
    """Diagnostic endpoint to check PowerShell job status"""
    try:
        result = subprocess.run(
            ["pwsh", "-Command", "Get-Job | Select-Object Name,State,HasMoreData,PSBeginTime,PSEndTime | ConvertTo-Json"],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        jobs_info = {
            "stdout": result.stdout,
            "stderr": result.stderr,
            "returncode": result.returncode,
            "timestamp": datetime.now().isoformat()
        }
        
        return f"<pre>{json.dumps(jobs_info, indent=2)}</pre>"
    except Exception as e:
        return f"<pre>Error checking jobs: {str(e)}</pre>"

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
    <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>☁️</text></svg>">
    <title>ARI Reports</title>
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
                
                <div style="background: #f0f9ff; padding: 20px; border-radius: 12px; margin: 15px 0; text-align: center; border: 2px solid #0078d4;">
                    <strong style="color: #0078d4; display: block; margin-bottom: 12px; font-size: 18px;">🔗 Step 1: Click to open login page</strong>
                    <a href="{url}" target="_blank" style="display: inline-block; background: #0078d4; color: white; padding: 16px 32px; text-decoration: none; border-radius: 8px; font-weight: bold; font-size: 16px; margin: 5px; transition: background-color 0.3s ease; box-shadow: 0 4px 12px rgba(0, 120, 212, 0.3);" onmouseover="this.style.backgroundColor='#106ebe'" onmouseout="this.style.backgroundColor='#0078d4'">{url}</a>
                </div>
                
                <div style="background: #f0f9ff; padding: 18px; border-radius: 12px; margin: 15px 0; text-align: center; border: 2px solid #0078d4;">
                    <strong style="color: #0078d4; display: block; margin-bottom: 12px; font-size: 16px;">🔑 Step 2: Enter this code</strong>
                    <div style="background: #ffffff; padding: 10px 18px; font-size: 28px; font-weight: bold; border-radius: 8px; color: #0078d4; font-family: 'Segoe UI', monospace; letter-spacing: 3px; margin: 8px 0; display: inline-block; box-shadow: 0 2px 8px rgba(0, 120, 212, 0.15); border: 2px solid #e3f2fd;">{code}</div>
                    <br>
                    <button onclick="navigator.clipboard.writeText('{code}'); this.innerHTML='✅ Copied!'; setTimeout(() => this.innerHTML='📋 Copy Code', 2000);" style="margin-top: 12px; background: #0078d4; color: white; border: none; padding: 12px 24px; border-radius: 8px; cursor: pointer; font-weight: bold; font-size: 15px; transition: all 0.3s ease; box-shadow: 0 4px 12px rgba(0, 120, 212, 0.3);" onmouseover="this.style.backgroundColor='#106ebe'; this.style.transform='translateY(-2px)';" onmouseout="this.style.backgroundColor='#0078d4'; this.style.transform='translateY(0)';">📋 Copy Code</button>
                </div>
            </div>'''
        else:
            enhanced = f'<div style="background: #e3f2fd; padding: 15px; border-radius: 8px; margin: 10px 0;"><strong style="color: #1976d2;">🌐 {line.strip()}</strong></div>'
    elif "https://microsoft.com/devicelogin" in line and "To sign in" not in line:
        # Standalone URL
        url = "https://microsoft.com/devicelogin"
        enhanced = f'<div style="background: #f0f9ff; padding: 25px; border-radius: 12px; margin: 20px 0; text-align: center; border: 2px solid #0078d4;"><strong style="color: #0078d4; display: block; margin-bottom: 15px; font-size: 18px;">🔗 Click to open login page:</strong><a href="{url}" target="_blank" style="display: inline-block; background: #0078d4; color: white; padding: 18px 36px; text-decoration: none; border-radius: 10px; font-weight: bold; font-size: 16px; transition: background-color 0.3s ease; box-shadow: 0 4px 12px rgba(0, 120, 212, 0.3);" onmouseover="this.style.backgroundColor='#106ebe'" onmouseout="this.style.backgroundColor='#0078d4'">{url}</a></div>'
    elif re.search(r'\b[A-Z0-9]{6,12}\b', line) and ("code" in line.lower() or "enter" in line.lower()):
        # Standalone device code - but exclude common words like "ENTERING"
        match = re.search(r'\b([A-Z0-9]{6,12})\b', line)
        if match:
            code = match.group(1)
            # Exclude common words that might match the pattern
            excluded_words = ['ENTERING', 'RUNNING', 'STARTING', 'TESTING', 'COMPLETE', 'ERROR', 'WARNING', 
                            'SUCCESS', 'FAILED', 'STOPPED', 'BLOCKED', 'TIMEOUT', 'MONITOR', 'INITIALIZED']
            
            # Only enhance if it's not an excluded word and looks like an actual device code
            # Real device codes typically have mixed letters and numbers or specific patterns
            if code not in excluded_words and (any(c.isdigit() for c in code) and any(c.isalpha() for c in code)):
                enhanced = f'<div style="background: linear-gradient(135deg, #e3f2fd 0%, #f8f9ff 100%); padding: 30px; border-radius: 16px; margin: 25px auto; text-align: center; border: 2px solid #0078d4; max-width: 600px; box-shadow: 0 8px 32px rgba(0, 120, 212, 0.15);"><strong style="color: #0078d4; display: block; margin-bottom: 20px; font-size: 22px; font-weight: 600;">🔑 Your Device Authentication Code</strong><div style="background: #ffffff; padding: 20px 30px; font-size: 36px; font-weight: bold; border-radius: 12px; color: #0078d4; font-family: \'Segoe UI\', monospace; letter-spacing: 4px; box-shadow: 0 6px 20px rgba(0, 120, 212, 0.2); border: 2px solid #e3f2fd; margin: 15px 0;">{code}</div><button onclick="navigator.clipboard.writeText(\'{code}\'); this.innerHTML=\'✅ Copied!\'; setTimeout(() => this.innerHTML=\'📋 Copy Code\', 2000);" style="margin-top: 20px; background: #0078d4; color: white; border: none; padding: 15px 30px; border-radius: 10px; cursor: pointer; font-weight: 600; font-size: 16px; transition: all 0.3s ease; box-shadow: 0 6px 20px rgba(0, 120, 212, 0.3);" onmouseover="this.style.backgroundColor=\'#106ebe\'; this.style.transform=\'translateY(-2px)\';" onmouseout="this.style.backgroundColor=\'#0078d4\'; this.style.transform=\'translateY(0)\';" >📋 Copy Code</button></div>'
            else:
                enhanced = line + "<br>"
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
        # Get parameters from URL if provided, but never use environment variables
        from markupsafe import escape
        tenant_param = escape(request.args.get("tenant", "").strip())
        subscription_param = escape(request.args.get("subscription", "").strip())
        error_message = escape(request.args.get("error", "").strip())
        
        # Create HTML template with enhanced validation
        html_template = '''<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>☁️</text></svg>">
    <title>ARI Device Login</title>
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
      .info-box { 
        background: #f0f9ff; 
        padding: 15px; 
        border-radius: 8px; 
        margin-bottom: 20px; 
        border-left: 4px solid #0078d4; 
        font-size: 0.9rem;
      }
      .info-box strong { 
        color: #0078d4; 
        font-weight: bold;
        font-size: 1.1em;
      }
      .error-box {
        background: #fee;
        padding: 15px;
        border-radius: 8px;
        margin-bottom: 20px;
        border-left: 4px solid #dc2626;
        font-size: 0.9rem;
        color: #991b1b;
      }
      .error-box strong {
        font-weight: bold;
        font-size: 1.1em;
      }
      .help-section {
        background: #fef3c7;
        padding: 12px;
        border-radius: 6px;
        margin-bottom: 20px;
        border-left: 3px solid #f59e0b;
        font-size: 0.85rem;
      }
      .help-section a {
        color: #d97706;
        font-weight: 600;
        text-decoration: none;
      }
      .help-section a:hover {
        text-decoration: underline;
      }
      .form-group { margin-bottom: 18px; }
      label { 
        display: block; 
        margin-bottom: 8px; 
        font-weight: 600; 
        color: #1e293b;
      }
      .field-help {
        display: block;
        font-size: 0.8rem;
        color: #64748b;
        margin-bottom: 8px;
        font-weight: 400;
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
        font-family: 'Courier New', monospace;
      }
      input:focus { 
        outline: none;
        border-color: #0078d4;
        background: #ffffff;
        box-shadow: 0 0 0 3px rgba(0, 120, 212, 0.15), 0 4px 8px rgba(0, 0, 0, 0.1);
        transform: translateY(-1px);
      }
      input.invalid {
        border-color: #dc2626;
        background: #fee;
      }
      input.valid {
        border-color: #10b981;
        background: #f0fdf4;
      }
      input::placeholder {
        color: #9ca3af;
        font-style: italic;
        font-weight: 400;
      }
      .validation-message {
        display: none;
        font-size: 0.8rem;
        margin-top: 5px;
        padding: 5px 10px;
        border-radius: 4px;
      }
      .validation-message.error {
        display: block;
        background: #fee;
        color: #991b1b;
      }
      .validation-message.success {
        display: block;
        background: #f0fdf4;
        color: #065f46;
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
      .run-button:disabled {
        background: #9ca3af;
        cursor: not-allowed;
        transform: none;
        box-shadow: none;
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
        <h1>Azure Authentication Setup</h1>
        <p>Enter your Azure credentials to continue</p>
      </div>
      
      <div class="content">
        <div class="info-box">
          <strong>🔒 Secure Authentication:</strong> Uses Azure CLI device login for secure authentication.
          <br><strong>Your credentials are never stored</strong> - authentication is handled directly by Microsoft Azure.
        </div>
        
        ERROR_MESSAGE_PLACEHOLDER
        
        <div class="help-section">
          ℹ️ <strong>Need help finding your Tenant ID or Subscription ID?</strong><br>
          Visit the <a href="https://portal.azure.com/#view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/Properties" target="_blank">Azure Portal</a> to find your Tenant ID, or use <a href="https://portal.azure.com/#view/Microsoft_Azure_Billing/SubscriptionsBlade" target="_blank">Subscriptions</a> to find your Subscription ID.
        </div>
        
        <form method="POST" id="auth-form">
          <div class="form-group">
            <label for="tenant">Tenant ID<span style="color: #dc2626;">*</span> (required):</label>
            <span class="field-help">Your Azure Active Directory tenant ID (GUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)</span>
            <input type="text" name="tenant" id="tenant" value="TENANT_VALUE" placeholder="00000000-0000-0000-0000-000000000000" required pattern="[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}">
            <div id="tenant-validation" class="validation-message"></div>
          </div>
          
          <div class="form-group">
            <label for="subscription">Subscription ID (optional):</label>
            <span class="field-help">Leave empty to use your default subscription, or enter a specific Subscription ID (GUID format)</span>
            <input type="text" name="subscription" id="subscription" value="SUBSCRIPTION_VALUE" placeholder="00000000-0000-0000-0000-000000000000 (optional)">
            <div id="subscription-validation" class="validation-message"></div>
          </div>
          
          <div style="text-align: center;">
            <button type="submit" class="run-button" id="submit-btn">Start Authentication</button>
          </div>
          
          <div class="back-link">
            <a href="/">← Back to Main Page</a>
          </div>
        </form>
      </div>
    </div>
    
    <script>
      // GUID/UUID validation pattern
      const guidPattern = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
      
      const tenantInput = document.getElementById('tenant');
      const subscriptionInput = document.getElementById('subscription');
      const tenantValidation = document.getElementById('tenant-validation');
      const subscriptionValidation = document.getElementById('subscription-validation');
      const submitBtn = document.getElementById('submit-btn');
      const form = document.getElementById('auth-form');
      
      function validateTenant() {
        const value = tenantInput.value.trim();
        
        if (!value) {
          tenantInput.className = 'invalid';
          tenantValidation.className = 'validation-message error';
          tenantValidation.textContent = '❌ Tenant ID is required';
          return false;
        }
        
        if (!guidPattern.test(value)) {
          tenantInput.className = 'invalid';
          tenantValidation.className = 'validation-message error';
          tenantValidation.textContent = '❌ Invalid format. Tenant ID must be a valid GUID (e.g., 12345678-1234-1234-1234-123456789012)';
          return false;
        }
        
        tenantInput.className = 'valid';
        tenantValidation.className = 'validation-message success';
        tenantValidation.textContent = '✅ Valid Tenant ID format';
        return true;
      }
      
      function validateSubscription() {
        const value = subscriptionInput.value.trim();
        
        // Empty is valid (optional field)
        if (!value) {
          subscriptionInput.className = '';
          subscriptionValidation.className = 'validation-message';
          subscriptionValidation.style.display = 'none';
          return true;
        }
        
        if (!guidPattern.test(value)) {
          subscriptionInput.className = 'invalid';
          subscriptionValidation.className = 'validation-message error';
          subscriptionValidation.textContent = '❌ Invalid format. Subscription ID must be a valid GUID (e.g., 12345678-1234-1234-1234-123456789012)';
          return false;
        }
        
        subscriptionInput.className = 'valid';
        subscriptionValidation.className = 'validation-message success';
        subscriptionValidation.textContent = '✅ Valid Subscription ID format';
        return true;
      }
      
      function updateSubmitButton() {
        const tenantValid = validateTenant();
        const subscriptionValid = validateSubscription();
        submitBtn.disabled = !(tenantValid && subscriptionValid);
      }
      
      // Validate on input
      tenantInput.addEventListener('input', updateSubmitButton);
      subscriptionInput.addEventListener('input', updateSubmitButton);
      
      // Validate on blur
      tenantInput.addEventListener('blur', updateSubmitButton);
      subscriptionInput.addEventListener('blur', updateSubmitButton);
      
      // Initial validation
      updateSubmitButton();
      
      // Prevent form submission if validation fails
      form.addEventListener('submit', function(e) {
        if (!validateTenant() || !validateSubscription()) {
          e.preventDefault();
          alert('Please fix the validation errors before submitting.');
          return false;
        }
      });
    </script>
  </body>
</html>'''
        
        # Add error message if present
        if error_message:
            error_html = f'''<div class="error-box">
          <strong>⚠️ Error:</strong> {error_message}
        </div>'''
            html_template = html_template.replace("ERROR_MESSAGE_PLACEHOLDER", error_html)
        else:
            html_template = html_template.replace("ERROR_MESSAGE_PLACEHOLDER", "")
        
        # Replace placeholders safely - never use environment variables
        html_template = html_template.replace("TENANT_VALUE", tenant_param)
        html_template = html_template.replace("SUBSCRIPTION_VALUE", subscription_param)
        
        return html_template
    
    # POST request - validate inputs before starting Azure CLI device login process
    tenant = request.form.get("tenant", "").strip()
    subscription = request.form.get("subscription", "").strip()
    
    # Server-side validation - GUID format check
    guid_pattern = re.compile(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
    
    # Tenant ID is required
    if not tenant:
        return redirect(url_for('cli_device_login', error='Tenant ID is required. Please enter a valid Azure Tenant ID.'))
    
    # Validate Tenant ID format
    if not guid_pattern.match(tenant):
        return redirect(url_for('cli_device_login', 
                                tenant=tenant, 
                                subscription=subscription,
                                error='Invalid Tenant ID format. Tenant ID must be a valid GUID (e.g., 12345678-1234-1234-1234-123456789012).'))
    
    # Validate Subscription ID format if provided
    if subscription and not guid_pattern.match(subscription):
        return redirect(url_for('cli_device_login', 
                                tenant=tenant, 
                                subscription=subscription,
                                error='Invalid Subscription ID format. Subscription ID must be a valid GUID (e.g., 12345678-1234-1234-1234-123456789012).'))
    
    # Convert empty subscription to None
    subscription = subscription if subscription else None
    
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
    
    # Save job to disk for persistence
    save_job(job_id, jobs[job_id])
    
    # Start CLI job
    thread = threading.Thread(target=run_cli_job, args=(job_id, cli_script))
    thread.daemon = True
    thread.start()
    
    return '''<!doctype html>
<html>
  <head>
    <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>⚙️</text></svg>">
    <title>ARI Processing</title>
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
        const maxChecks = 1350; // 45 minutes (1350 * 2 seconds) - Enhanced error detection prevents hanging
        let lastOutputLength = 0;
        let processingStartTime = null;
        let sessionExpiredHandled = false; // Flag to prevent duplicate restart buttons
        let interval = null; // Declare interval variable early
        
        function checkOutput() {
          // Skip if session expired is already being handled
          if (sessionExpiredHandled) {
            if (interval) clearInterval(interval);
            return;
          }
          
          checkCount++;
          fetch(`/job-status/${jobId}`)
            .then(response => response.json())
            .then(data => {
              // Double-check the flag after async operation
              if (sessionExpiredHandled) {
                if (interval) clearInterval(interval);
                return;
              }
              
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
                        output.includes('ERROR: Failed to authenticate') ||
                        output.includes('ERROR: Failed to set subscription') ||
                        output.includes('ERROR: Tenant ID is required') ||
                        output.includes('Process failed with exit code')) {
                statusElement.className = 'status';
                statusElement.style.background = '#fef2f2';
                statusElement.style.borderLeftColor = '#ef4444';
                statusElement.style.color = '#991b1b';
                
                // Provide specific error messages
                if (output.includes('Failed to authenticate with the provided Tenant ID')) {
                  statusElement.innerHTML = '❌ Authentication failed - Invalid Tenant ID. Please verify your Tenant ID and <a href="/cli-device-login" style="color: #991b1b; font-weight: bold; text-decoration: underline;">try again</a>.';
                } else if (output.includes('Failed to set subscription')) {
                  statusElement.innerHTML = '❌ Authentication failed - Invalid or inaccessible Subscription ID. Please verify your Subscription ID and <a href="/cli-device-login" style="color: #991b1b; font-weight: bold; text-decoration: underline;">try again</a>.';
                } else {
                  statusElement.innerHTML = '❌ Authentication failed - Please check your Azure credentials and <a href="/cli-device-login" style="color: #991b1b; font-weight: bold; text-decoration: underline;">try again</a>.';
                }
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
              } else if (data.status === 'not_found') {
                sessionExpiredHandled = true; // Set flag immediately
                clearInterval(interval); // Clear interval immediately
                
                console.log('Job not found - likely expired or container restarted');
                const statusElement = document.querySelector('.status');
                statusElement.className = 'status';
                statusElement.style.background = '#fff3cd';
                statusElement.style.borderLeftColor = '#ffc107';
                statusElement.style.color = '#856404';
                statusElement.innerHTML = '⚠️ Session expired. Please start a new Azure Resource Inventory scan.';
                // Show single restart button after delay
                setTimeout(() => {
                  // Only add button if it doesn't already exist
                  if (!document.querySelector('.restart-scan-btn')) {
                    const restartBtn = document.createElement('button');
                    restartBtn.className = 'restart-scan-btn';
                    restartBtn.innerHTML = '🔄 Start New Scan';
                    restartBtn.style.cssText = 'margin-top: 15px; background: #0078d4; color: white; border: none; padding: 12px 24px; border-radius: 8px; cursor: pointer; font-weight: bold; transition: all 0.3s ease;';
                    restartBtn.onmouseover = () => restartBtn.style.backgroundColor = '#106ebe';
                    restartBtn.onmouseout = () => restartBtn.style.backgroundColor = '#0078d4';
                    restartBtn.onclick = () => window.location.href = '/';
                    statusElement.appendChild(document.createElement('br'));
                    statusElement.appendChild(restartBtn);
                  }
                }, 500);
              } else if (data.status === 'failed' || checkCount >= maxChecks) {
                clearInterval(interval);
                const spinner = document.querySelector('.spinner');
                if (spinner) spinner.style.display = 'none';
                
                // Add a delay before checking files to ensure they're fully written
                // This prevents race condition where frontend checks before files are flushed
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
        
        interval = setInterval(checkOutput, 2000);
        checkOutput();
      </script>
    </div>
  </body>
</html>'''


@app.route("/job-status/<job_id>")
def get_job_status(job_id):
    """Get the status and output of a running job"""
    # Try to get from memory first
    job = jobs.get(job_id)
    
    # If not in memory, try loading from disk
    if not job:
        job = load_job(job_id)
        if job:
            jobs[job_id] = job  # Restore to memory
    
    if not job:
        # Instead of 404, return a "not found" status to prevent log spam
        return jsonify({
            'status': 'not_found',
            'output': 'Job not found. It may have expired or the container was restarted.',
            'created_at': None
        }), 200
    
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
    
    # Add error handling for tenant validation
    if tenant:
        script_parts.extend([
            f"echo 'Attempting login with Tenant ID: {tenant}'",
            f"if ! az login --tenant '{tenant}' --use-device-code 2>&1; then",
            "    echo '❌ ERROR: Failed to authenticate with the provided Tenant ID.'",
            f"    echo '❌ Please verify that Tenant ID \"{tenant}\" is correct and try again.'",
            "    echo 'ℹ️ You can find your Tenant ID in the Azure Portal under Azure Active Directory > Properties.'",
            "    exit 1",
            "fi"
        ])
    else:
        # This should never happen due to server-side validation, but just in case
        script_parts.extend([
            "echo '❌ ERROR: Tenant ID is required but was not provided.'",
            "echo 'ℹ️ Please return to the form and enter your Azure Tenant ID.'",
            "exit 1"
        ])
    
    if subscription:
        script_parts.extend([
            f"echo 'Setting subscription to: {subscription}'",
            f"if ! az account set --subscription '{subscription}' 2>&1; then",
            "    echo '❌ ERROR: Failed to set subscription. The Subscription ID may be incorrect or you may not have access.'",
            f"    echo '❌ Please verify that Subscription ID \"{subscription}\" is correct and you have access to it.'",
            "    echo 'ℹ️ You can find your Subscription IDs in the Azure Portal under Subscriptions.'",
            "    exit 1",
            "fi"
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
        "# Clear Azure File Share before ARI execution (if configured)",
        "echo ''",
        "echo '======================================='",
        "echo '🧹 AZURE FILE SHARE CLEANUP'",
        "echo '======================================='",
        "echo ''",
        "",
        "# Enable strict error handling for cleanup section",
        "# This ensures any unexpected errors cause immediate failure",
        "# The PowerShell cleanup script exit code is explicitly checked below",
        "set -e",
        "",
        "if [ ! -z \"$AZURE_STORAGE_ACCOUNT\" ] && [ ! -z \"$AZURE_STORAGE_KEY\" ] && [ ! -z \"$AZURE_FILE_SHARE\" ]; then",
        "    echo '📦 Azure Storage configuration found:'",
        "    echo \"   Storage Account: $AZURE_STORAGE_ACCOUNT\"",
        "    echo \"   File Share: $AZURE_FILE_SHARE\"",
        "    echo ''",
        "    echo '🔄 Running file share cleanup...'",
        "    echo '   This ensures a clean state for report generation'",
        "    echo '   Protected folders (.jobs, .snapshots, etc.) will be preserved'",
        "    echo ''",
        "",
        "    # Run cleanup script - if it fails, the entire job will fail due to 'set -e'",
        "    if pwsh -NoProfile -ExecutionPolicy Bypass -File /app/powershell/clear-azure-fileshare.ps1 \\",
        "        -StorageAccountName \"$AZURE_STORAGE_ACCOUNT\" \\",
        "        -StorageAccountKey \"$AZURE_STORAGE_KEY\" \\",
        "        -FileShareName \"$AZURE_FILE_SHARE\"; then",
        "        ",
        "        echo ''",
        "        echo '======================================='",
        "        echo '✅ CLEANUP SUCCESSFUL'",
        "        echo '======================================='",
        "        echo 'File share has been cleaned and is ready for ARI execution'",
        "        echo 'Protected system folders have been preserved'",
        "        echo ''",
        "    else",
        "        CLEANUP_EXIT_CODE=$?",
        "        echo ''",
        "        echo '======================================='",
        "        echo '❌ CLEANUP FAILED - BLOCKING ARI EXECUTION'",
        "        echo '======================================='",
        "        echo \"File share cleanup failed with exit code: $CLEANUP_EXIT_CODE\"",
        "        echo ''",
        "        echo '🚫 CRITICAL ERROR: ARI execution cannot proceed'",
        "        echo ''",
        "        echo '📋 Why cleanup is critical:'",
        "        echo '   • Old report files may interfere with new reports'",
        "        echo '   • Stale diagrams could cause confusion'",
        "        echo '   • File share capacity could be exhausted'",
        "        echo '   • Data consistency cannot be guaranteed'",
        "        echo ''",
        "        echo '🔍 Common causes of cleanup failure:'",
        "        echo '   • Invalid storage account credentials (most common)'",
        "        echo '   • Network connectivity issues to Azure Storage'",
        "        echo '   • File share does not exist or has been deleted'",
        "        echo '   • Files are locked by another process or container'",
        "        echo '   • Insufficient permissions on storage account'",
        "        echo '   • Azure Storage firewall blocking access'",
        "        echo '   • Storage account key has been rotated'",
        "        echo ''",
        "        echo '🛠️ Troubleshooting steps:'",
        "        echo '   1. Verify environment variables are correct:'",
        "        echo '      • AZURE_STORAGE_ACCOUNT (current: $AZURE_STORAGE_ACCOUNT)'",
        "        echo '      • AZURE_FILE_SHARE (current: $AZURE_FILE_SHARE)'",
        "        echo '      • AZURE_STORAGE_KEY (verify key is current and not rotated)'",
        "        echo ''",
        "        echo '   2. Test storage account access:'",
        "        echo '      az storage account show --name $AZURE_STORAGE_ACCOUNT'",
        "        echo ''",
        "        echo '   3. Verify file share exists:'",
        "        echo '      az storage share show --name $AZURE_FILE_SHARE --account-name $AZURE_STORAGE_ACCOUNT'",
        "        echo ''",
        "        echo '   4. Check firewall rules:'",
        "        echo '      az storage account show --name $AZURE_STORAGE_ACCOUNT --query networkRuleSet'",
        "        echo ''",
        "        echo '   5. Review detailed error messages in logs above'",
        "        echo ''",
        "        echo '   6. If using Managed Identity, verify it has Storage Blob Data Contributor role'",
        "        echo ''",
        "        echo '⚠️  IMPORTANT: This job has been BLOCKED and will NOT proceed'",
        "        echo '⚠️  until cleanup succeeds. This is intentional to maintain data integrity.'",
        "        echo ''",
        "        echo '💡 For emergency access (not recommended):'",
        "        echo '   • Remove cleanup environment variables to skip cleanup'",
        "        echo '   • Be aware that old files may remain in storage'",
        "        echo ''",
        "        ",
        "        # Exit immediately to block ARI execution",
        "        exit 1",
        "    fi",
        "",
        "    # Disable strict error handling after cleanup",
        "    set +e",
        "else",
        "    echo '⚠️  Azure Storage environment variables not configured'",
        "    echo ''",
        "    echo 'File share cleanup is DISABLED because required environment'",
        "    echo 'variables are not set. ARI will proceed without cleanup.'",
        "    echo ''",
        "    echo '📋 To enable automatic cleanup, configure these environment variables:'",
        "    echo '  • AZURE_STORAGE_ACCOUNT - The name of your Azure Storage Account'",
        "    echo '  • AZURE_STORAGE_KEY - The access key for your Azure Storage Account'",
        "    echo '  • AZURE_FILE_SHARE - The name of the Azure File Share to clean'",
        "    echo ''",
        "    echo '⚠️  WARNING: Without cleanup, old reports will accumulate in storage'",
        "    echo '   This may cause:'",
        "    echo '   • Confusion from outdated reports'",
        "    echo '   • Increased storage costs'",
        "    echo '   • Potential storage capacity issues'",
        "    echo ''",
        "    echo '✅ Proceeding without cleanup (cleanup not configured)'",
        "    echo ''",
        "    ",
        "    # Disable strict error handling since cleanup was skipped",
        "    set +e",
        "fi",
        "echo '======================================='",
        "echo ''",
        "",
        "# Create PowerShell script file with robust error handling",
        "cat > /tmp/run_ari.ps1 << 'EOF'",
        "$ErrorActionPreference = 'Stop'",
        "",
        "Write-Host 'Setting up Azure Resource Inventory module...' -ForegroundColor Green",
        "try {",
        "    # ===== TESTING MODE: Use pre-installed local module =====",
        "    # The module is already copied to /usr/local/share/powershell/Modules/ during Docker build",
        "    Write-Host '🧪 TESTING MODE: Using local modified AzureResourceInventory module' -ForegroundColor Yellow",
        "    ",
    "    # Diagnostics: show PSModulePath and possible AzureResourceInventory directories",
    "    Write-Host '🔎 PSModulePath:' -ForegroundColor Cyan",
    "    $env:PSModulePath -split ':' | ForEach-Object { Write-Host \"  -> $_\" -ForegroundColor DarkCyan }",
    "    Write-Host '🔎 Searching for AzureResourceInventory module directories...' -ForegroundColor Cyan",
    "    Get-ChildItem -Path /usr/local/share/powershell/Modules/AzureResourceInventory -ErrorAction SilentlyContinue | ForEach-Object { Write-Host \"  Top-Level: $($_.FullName)\" -ForegroundColor DarkGray }",
    "    Get-ChildItem -Path /usr/local/share/powershell/Modules/AzureResourceInventory -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -and ($_.Name -match '3\\.6\\.') } | ForEach-Object { Write-Host \"  Version Dir: $($_.FullName)\" -ForegroundColor DarkGray }",
    "    if (Test-Path /usr/local/share/powershell/Modules/AzureResourceInventory) {",
    "      Write-Host 'Structure under /usr/local/share/powershell/Modules/AzureResourceInventory:' -ForegroundColor DarkCyan",
    "      Get-ChildItem /usr/local/share/powershell/Modules/AzureResourceInventory | ForEach-Object { Write-Host \"   - $($_.Name)\" -ForegroundColor DarkCyan }",
    "    }",
    "    if (Get-Module -ListAvailable -Name AzureResourceInventory) {",
        "        Import-Module AzureResourceInventory -Force -ErrorAction Stop",
        "        Write-Host '✅ Local testing module imported successfully!' -ForegroundColor Green",
        "        $moduleInfo = Get-Module AzureResourceInventory",
        "        Write-Host \"Module Path: $($moduleInfo.ModuleBase)\" -ForegroundColor Cyan",
        "    } else {",
        "        Write-Error 'TESTING MODE module not found! Docker image may not have been built correctly.'",
        "        exit 1",
        "    }",
        "    # ===== END TESTING MODE =====",
        "} catch {",
        "    Write-Error \"Failed to setup AzureResourceInventory module: $($_.Exception.Message)\"",
        "    exit 1",
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
        "# Get current tenant and subscription info",
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
        "    Write-Host '⏳ Azure Resource Inventory is now running...' -ForegroundColor Yellow",
        "    Write-Host 'This process scans all resources in your subscription and may take 10-30 minutes.' -ForegroundColor Yellow",
        "    Write-Host 'The screen may appear quiet while ARI works - this is normal.' -ForegroundColor Yellow",
        "    Write-Host 'Please be patient while we analyze your Azure environment.' -ForegroundColor Yellow",
        "    Write-Host ''",
        "    ",
        "    # Execute ARI with enhanced progress tracking and error detection",
        "    $startTime = Get-Date",
        "    ",
        "    Write-Host \"🚀 Starting ARI execution...\" -ForegroundColor Green",
        "    Write-Host \"⏰ This may take 10-45 minutes depending on your environment size\" -ForegroundColor Yellow",
        "    Write-Host \"📊 The process will generate reports in: $reportDir\" -ForegroundColor Cyan",
        "    Write-Host ''",
        "    ",
        "    # Run ARI directly with explicit error handling that doesn't require re-importing the module",
        "    try {",
        "        Invoke-ARI -ReportDir $reportDir -ReportName $reportName -TenantID $tenantId -SubscriptionID $subscriptionId -Debug -NoAutoUpdate -ErrorAction Stop",
        "        ",
        "        $endTime = Get-Date",
        "        $duration = $endTime - $startTime",
        "        Write-Host \"\\n✅ ARI execution completed in $($duration.TotalMinutes.ToString('0.0')) minutes!\" -ForegroundColor Green",
        "        Write-Host 'Azure Resource Inventory completed successfully!' -ForegroundColor Green",
        "    } catch {",
        "        $endTime = Get-Date",
        "        $duration = $endTime - $startTime",
        "        Write-Host \"\\n⚠️ ARI execution encountered an error after $($duration.TotalMinutes.ToString('0.0')) minutes\" -ForegroundColor Yellow",
        "        Write-Host \"Error: $($_.Exception.Message)\" -ForegroundColor Red",
        "        Write-Host \"\\nNote: Some reports may have been generated despite the error.\" -ForegroundColor Yellow",
        "        Write-Host \"Checking output directory for any generated files...\" -ForegroundColor Cyan",
        "        ",
        "        # Don't exit with error - let the file check below determine if we have usable output",
        "    }",
        "",
        "",
        "# Check for generated files with enhanced debugging",
        "Write-Host ''",
        "Write-Host '📁 Checking for generated files...' -ForegroundColor Green",
        "Write-Host \"Report Directory: $reportDir\" -ForegroundColor Cyan",
        "Write-Host \"Directory exists: $(Test-Path $reportDir)\" -ForegroundColor Cyan",
        "",
        "$filesGenerated = $false",
        "if (Test-Path $reportDir) {",
        "    $allFiles = Get-ChildItem -Path $reportDir -ErrorAction SilentlyContinue -Recurse",
        "    $reportFiles = $allFiles | Where-Object { -not $_.PSIsContainer -and ($_.Extension -in @('.xlsx', '.xml', '.csv', '.json', '.html')) }",
        "    ",
        "    Write-Host \"Total items in directory (including subdirs): $($allFiles.Count)\" -ForegroundColor Cyan",
        "    Write-Host \"Report files found: $($reportFiles.Count)\" -ForegroundColor Cyan",
        "    ",
        "    if ($reportFiles) {",
        "        $filesGenerated = $true",
        "        Write-Host ''",
        "        Write-Host '✅ Generated report files:' -ForegroundColor Green",
        "        $reportFiles | Select-Object Name, @{Name='Size(MB)';Expression={[math]::Round($_.Length/1MB,2)}}, LastWriteTime | Format-Table -AutoSize",
        "        Write-Host ''",
        "        Write-Host '📋 File paths:' -ForegroundColor Yellow",
        "        $reportFiles | ForEach-Object { Write-Host \"  ✓ $($_.FullName)\" -ForegroundColor Gray }",
        "        Write-Host ''",
        "        Write-Host '🎉 Reports successfully generated and ready for download!' -ForegroundColor Green",
        "        ",
        "        # Validate diagram files",
        "        Write-Host ''",
        "        Write-Host '🔍 Checking for diagram files...' -ForegroundColor Cyan",
        "        # Look for files with 'Diagram' in the name (case-insensitive) and specifically .xml files",
        "        # ARI generates diagrams in Draw.io XML format with 'Diagram' in the filename",
        "        $diagramFiles = $reportFiles | Where-Object { $_.Name -like '*Diagram*.xml' -or $_.Name -like '*diagram*.xml' }",
        "        ",
        "        if ($diagramFiles -and $diagramFiles.Count -gt 0) {",
        "            Write-Host \"✅ Found $($diagramFiles.Count) diagram file(s):\" -ForegroundColor Green",
        "            $diagramFiles | ForEach-Object { Write-Host \"   📊 $($_.Name)\" -ForegroundColor Green }",
        "            Write-Host ''",
        "            Write-Host '✅ DIAGRAM GENERATION: Successfully generated diagrams' -ForegroundColor Green",
        "        } else {",
        "            Write-Host '⚠️  WARNING: No diagram files found!' -ForegroundColor Yellow",
        "            Write-Host '   Diagram files typically have names like \"AzureResourceInventory_Diagram_*.xml\"' -ForegroundColor Yellow",
        "            Write-Host '   Diagram generation may have been skipped or failed during ARI execution' -ForegroundColor Yellow",
        "            Write-Host ''",
        "            Write-Host '📋 Troubleshooting:' -ForegroundColor Cyan",
        "            Write-Host '   - Diagram generation is enabled by default (no -SkipDiagram flag used)' -ForegroundColor Gray",
        "            Write-Host '   - Check if your Azure environment has network resources (VNets, NSGs, etc.)' -ForegroundColor Gray",
        "            Write-Host '   - Review the ARI execution output above for diagram-related errors' -ForegroundColor Gray",
        "            Write-Host ''",
        "        }",
        "    } else {",
        "        Write-Host ''",
        "        Write-Warning '⚠️ No report files (.xlsx, .xml, .csv, .json, .html) found in output directory'",
        "        Write-Host ''",
        "        if ($allFiles) {",
        "            Write-Host '📂 Directory contents (non-report files):' -ForegroundColor Yellow",
        "            $allFiles | Where-Object { -not $_.PSIsContainer } | ForEach-Object { ",
        "                Write-Host \"  - $($_.Name) (Type: $($_.Extension))\" -ForegroundColor Gray ",
        "            }",
        "        }",
        "    }",
        "} else {",
        "    Write-Warning '⚠️ Output directory not found!'",
        "    Write-Host \"Attempting to create directory: $reportDir\" -ForegroundColor Yellow",
        "    try {",
        "        New-Item -Path $reportDir -ItemType Directory -Force | Out-Null",
        "        Write-Host '✅ Directory created successfully' -ForegroundColor Green",
        "    } catch {",
        "        Write-Error \"❌ Failed to create directory: $_\"",
        "    }",
        "}",
        "",
        "# Exit with appropriate code based on whether files were generated",
        "if ($filesGenerated) {",
        "    Write-Host ''",
        "    Write-Host '=' * 70 -ForegroundColor Green",
        "    Write-Host '  SUCCESS: Azure Resource Inventory completed with generated reports  ' -ForegroundColor Green",
        "    Write-Host '=' * 70 -ForegroundColor Green",
        "    exit 0",
        "} else {",
        "    Write-Host ''",
        "    Write-Host '=' * 70 -ForegroundColor Yellow",
        "    Write-Host '  WARNING: Process completed but no report files were generated  ' -ForegroundColor Yellow",
        "    Write-Host '=' * 70 -ForegroundColor Yellow",
        "    exit 1",
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
        save_job(job_id, jobs[job_id])  # Save after update
        
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
        last_save_time = time.time()
        for line in iter(process.stdout.readline, ''):
            if line:
                line_count += 1
                # Print every line to container logs for debugging
                print(f"[JOB {job_id}] LINE {line_count}: {line.strip()}")
                
                # Enhance device code formatting
                enhanced_line = enhance_device_code_output(line)
                jobs[job_id]['output'] += enhanced_line
                
                # Save to disk every 10 seconds to avoid too many writes
                current_time = time.time()
                if current_time - last_save_time > 10:
                    save_job(job_id, jobs[job_id])
                    last_save_time = current_time
        
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
        
        # Final save
        save_job(job_id, jobs[job_id])
            
    except Exception as e:
        print(f"[JOB {job_id}] EXCEPTION: {str(e)}")
        jobs[job_id]['status'] = 'failed'
        jobs[job_id]['output'] += f"<br>Error: {str(e)}"
        save_job(job_id, jobs[job_id])  # Save on error


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    app.run(host="0.0.0.0", port=port)