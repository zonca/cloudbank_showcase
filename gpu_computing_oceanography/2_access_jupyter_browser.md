# 2 - Access Jupyter Notebook via Browser

Goal: Configure firewall rules and access the Jupyter notebook running on your GPU instance through a web browser. This provides the simplest access method and works in any web browser.

**Advantages of browser-based Jupyter:**
- No local software installation required
- Works on any device with a web browser
- Quick setup - just open firewall and access via URL
- Perfect for Chromebooks and mobile devices

## Prerequisites
- Completed tutorial 1 (GPU instance created)
- Jupyter not yet running on the server

### Step 1: Launch Jupyter notebook securely
Ask Gemini to start Jupyter with authentication enabled:
```
SSH into the server and launch Jupyter notebook using IJulia with authentication enabled using a token. Make it run in detached mode so it stays running in the background. Do not disable authentication. Make the Jupyter server accessible over the network.
```

**Julia command:**
```bash
julia -e "using IJulia; notebook(dir=pwd(), detached=true, token=true)"
```

**Security note:** This ensures Jupyter requires a token for access, preventing unauthorized access to your notebook and GPU instance.

## Open firewall port for Jupyter

### Step 2: Allow Jupyter port access
Ask Gemini to create a firewall rule to allow access to Jupyter:
```
Create a firewall rule to allow access to port 8888 for Jupyter notebook. The rule should allow TCP traffic from any IP address.
Then show the the full connection url for Jupyter including the external IP and the token
```

**Expected firewall rule creation:**
```bash
gcloud compute firewall-rules create allow-jupyter \
  --allow tcp:8888 \
  --source-ranges 0.0.0.0/0 \
  --description "Allow Jupyter notebook access"
```

Gemini will also provide the connection URL with a token, typically looking like:
```
http://xxx.xxx.xxx.xxx:8888/?token=abcdef1234567890...
```

### Step 3: Open in the browser
Paste the URL from the previous step into your web browser to access the Jupyter notebook interface.

**Important:** Don't share the token URL with others. The token provides secure access to your Jupyter notebook and GPU instance.

### Step 4: Verify GPU access
In Jupyter, create a new Julia notebook and run:

```julia
using CUDA
CUDA.versioninfo()
```

Expected output should show:
```
CUDA toolchain: 
- runtime 13.2, artifact installation
- driver 535.288.1 for 13.2
- compiler 13.2

CUDA libraries: 
- CUBLAS: 13.3.0
- CURAND: 10.4.2
- CUFFT: 12.2.0
- CUSOLVER: 12.1.0
- CUSPARSE: 12.7.9
- CUPTI: 2026.1.0 (API 13.2.0)
- NVML: 12.0.0+535.288.1

Julia packages: 
- CUDA: 5.11.0
- GPUArrays: 11.4.1
- GPUCompiler: 1.9.1
- KernelAbstractions: 0.9.41
- CUDA_Driver_jll: 13.2.0+0
- CUDA_Compiler_jll: 0.4.2+0
- CUDA_Runtime_jll: 0.21.0+0

Toolchain:
- Julia: 1.11.9
- LLVM: 16.0.6

1 device:
  0: Tesla T4 (sm_75, 14.576 GiB / 15.000 GiB available)
```

## Upload the tutorial notebook
1. In Jupyter, click **Upload** in the top right corner
2. Select the `ocean_gpu_tutorial.ipynb`, `ocean_utils.jl`, and `Project.toml` files from your local machine
3. Click **Upload** to confirm
4. Open the tutorial notebook to begin the ocean modeling tutorial

## Security considerations
**Important:** The firewall rule allows access from any IP address. When you're done working:
1. Delete the firewall rule:
   ```bash
   gcloud compute firewall-rules delete allow-jupyter
   ```
2. Stop the instance if not needed:
   ```bash
   gcloud compute instances stop julia-ocean-gpu --zone=us-west1-b
   ```

## Troubleshooting
- **Connection refused:** Ensure Jupyter is running and the firewall rule is in place
- **Token not found:** Ask Gemini to show the latest Jupyter logs to find the correct token
- **Slow performance:** This is normal during first GPU compilation; subsequent runs will be much faster

## Alternative access method
If you prefer using VS Code instead of browser-based Jupyter for a full IDE experience, see tutorial [`3_access_jupyter_vscode.md`](3_access_jupyter_vscode.md).
