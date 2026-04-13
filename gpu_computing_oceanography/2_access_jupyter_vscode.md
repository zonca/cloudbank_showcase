# 2 - Access Jupyter with VS Code

Goal: Configure VS Code to connect to your GPU instance and run Jupyter notebooks with full IDE capabilities.

## Prerequisites
- Completed tutorial 1 (GPU instance created and Julia packages installed)
- VS Code installed on your local machine
- VS Code Python and Julia extensions installed

## Option: Install VS Code Server (simpler alternative)
If you prefer a completely browser-based experience similar to Jupyter, ask Gemini:
```
SSH into the server and install code-server.
```

**Installation:**
```bash
curl -fsSL https://code-server.dev/install.sh | sh
```

Then create a firewall rule and access code-server at `http://EXTERNAL_IP:8080`.

## Access from local VS Code

### Step 1: Get SSH connection details
Ask Gemini for the SSH connection information:
```
Show me the SSH connection command for the server.
```

**Expected command:**
```bash
gcloud compute ssh julia-ocean-gpu --zone=us-west1-b
```

### Step 2: Open VS Code Remote SSH

**In your local VS Code:**
1. Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac)
2. Type "Remote-SSH: Connect to Host" and select it
3. Choose "Add New SSH Host"
4. Paste the SSH command above
5. Choose the SSH config file location (usually default)
6. Press Enter to confirm

**Alternative method - use gcloud integration:**
1. Install the "Cloud Code" extension in VS Code
2. Click the Cloud Code icon in the sidebar
3. Navigate to your Google Cloud project
4. Right-click on `julia-ocean-gpu` instance
5. Select "SSH in terminal" and then "Open in VS Code"

### Step 3: Connect to the server
1. In the Remote-SSH panel, click the new host (`julia-ocean-gpu`)
2. Wait for VS Code to connect to the server
3. A new VS Code window will open with the server's files

### Step 4: Install VS Code extensions on server
Once connected, VS Code will prompt you to install extensions on the server. Install:

**Required extensions:**
- **Julia** - Julia language support and notebook rendering
- **Python** - For Jupyter support
- **Jupyter** - For notebook integration

**Optional but recommended:**
- **GitLens** - Enhanced Git capabilities
- **Remote Development** - Additional remote tools

### Step 5: Verify Julia environment

**In VS Code remote terminal:**
```bash
julia --version
```

Expected output: `julia version 1.11.9`

### Step 6: Upload or clone the notebook

**Option A - Clone repository:**
```bash
git clone https://github.com/zonca/cloudbank_showcase.git
cd cloudbank_showcase/gpu_computing_oceanography
```

**Option B - Upload notebook:**
1. In VS Code's file explorer, right-click and select "Upload Files"
2. Select `Julia_demo.ipynb` from your local machine
3. Wait for the upload to complete

### Step 7: Open the notebook

**Open the Julia notebook:**
1. Navigate to `gpu_computing_oceanography/Julia_demo.ipynb`
2. Right-click the file and select "Open with VS Code"
3. Select Julia as the kernel when prompted
4. VS Code will render the notebook beautifully with inline plots

### Step 8: Verify GPU access

**In the first code cell of the notebook, run:**
```julia
using CUDA
CUDA.versioninfo()
```

Expected output:
```
CUDA toolchain: 
- runtime 12.1, artifact installation
- driver 535.288.1 for 13.2
- compiler 12.9

CUDA libraries: 
- CUBLAS: 12.1.3
- CURAND: 10.3.2
- CUFFT: 11.0.2
- CUSOLVER: 11.4.5
- CUSPARSE: 12.1.0
- CUPTI: 2023.1.1 (API 11.8.0)
- NVML: 12.0.0+535.288.1

1 device:
  0: Tesla T4 (sm_75, 14.576 GiB / 15.000 GiB available)
```

## Advantages of VS Code over browser Jupyter

**Better editing:**
- Syntax highlighting and IntelliSense for Julia
- Multiple code cells visible at once
- Easy debugging and error navigation

**Enhanced features:**
- Integrated terminal for running shell commands
- Git integration for version control
- Extensions for additional functionality
- Better visual design and usability

**Performance:**
- Native desktop application performance
- Better handling of large notebooks
- Advanced search and replace capabilities

## Troubleshooting

**Connection issues:**
- Ensure `gcloud compute ssh` works from your local terminal
- Check your VS Code Remote-SSH extension is installed
- Try restarting the remote connection

**Julia kernel issues:**
- Run `julia -e "using IJulia; installkernel("Julia")"` in the remote terminal
- Ensure Julia 1.11.9 is the default version
- Check that IJulia is properly installed

**GPU not detected:**
- Verify `nvidia-smi` shows the GPU
- Check CUDA is working in Julia
- Ensure drivers are properly installed

## Next steps
Now you're ready to run the Julia ocean modeling tutorial:
1. Open `Julia_demo.ipynb` in VS Code
2. Run cells sequentially to set up the environment
3. Execute the differentiable ocean dynamics simulation
4. Visualize results with GPU-accelerated rendering

## Cleanup
When you're done:
```bash
# From Cloud Shell (not inside the instance)
gcloud compute instances stop julia-ocean-gpu --zone=us-west1-b
gcloud compute instances delete julia-ocean-gpu --zone=us-west1-b
```

## Alternative access method
If you prefer using browser-based Jupyter instead of VS Code, see tutorial [`2_access_jupyter_browser.md`](2_access_jupyter_browser.md).
