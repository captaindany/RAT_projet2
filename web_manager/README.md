# RAT Web Manager

This is a Flask-based web dashboard to manage the existing Rust RAT project without modifying its source code. 
It provides a premium, modern interface to:
- Start and stop the C2 server
- Build agent payloads (for Linux x86_64, aarch64)
- List active agents
- Execute commands remotely on active agents

## Requirements
- Python 3.8+
- The `rat` project directory must be accessible (containing `Cargo.toml`, `Makefile`, etc.)
- Rust (`cargo`) and `make` must be installed on the Linux machine for building agents and running the client/server.

## Deployment Instructions (Linux)

1. Copy this `web_manager` folder to your target Linux machine. Place it next to the `RAT_projet-main` folder, so its path is `.../RAT_projet-main/web_manager`.
   *(If you place it elsewhere, you'll need to set the `RAT_DIR` environment variable).*

2. Navigate to the copied folder:
   ```bash
   cd web_manager
   ```

3. Install the required Python dependencies. (Using a virtual environment is highly recommended):
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

4. Start the dashboard:
   ```bash
   # Optional: if the "rat" project is located somewhere else, you can set:
   # export RAT_DIR=/path/to/rat
   
   python3 app.py
   ```

5. Access the dashboard from your web browser at:
   `http://<IP_OF_LINUX_MACHINE>:5000`

## Architecture
- **Backend (Python/Flask)**: Exposes REST API endpoints (`/api/server/start`, `/api/agents/exec`, etc.). It uses Python's `subprocess` to call the already existing `cargo run` and `make` commands of the RAT project.
- **Frontend (Vanilla HTML/CSS/JS)**: A single-page dashboard featuring a dark mode, glassmorphism design that communicates with the Flask backend asynchronously.
