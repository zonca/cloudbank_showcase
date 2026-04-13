# 2 - Access Jupyter Notebook via Browser

Goal: Configure firewall rules and access the Jupyter notebook running on your GPU instance through a web browser. This provides the simplest access method and works in any web browser.

**Advantages of browser-based Jupyter:**
- No local software installation required
- Works on any device with a web browser
- Quick setup - just open firewall and access via URL
- Perfect for Chromebooks and mobile devices

## Prerequisites
- Completed tutorial 1 (GPU instance created and Jupyter notebook running)
- Jupyter notebook is currently running in detached mode on the server

## Open firewall port for Jupyter

### Step 1: Allow Jupyter port access
Ask Gemini to create a firewall rule to allow access to Jupyter:
```
Create a firewall rule to allow access to port 8888 for Jupyter notebook. The rule should allow TCP traffic from any IP address.
```

**Expected firewall rule creation:**
```bash
gcloud compute firewall-rules create allow-jupyter \
  --allow tcp:8888 \
  --source-ranges 0.0.0.0/0 \
  --description "Allow Jupyter notebook access"
```

### Step 2: Get connection information
Ask Gemini to retrieve the Jupyter connection details:
```
Show me the Jupyter notebook connection details including the URL and token from the server.
```

Gemini will provide the connection URL with a token, typically looking like:
```
http://0.0.0.0:8888/?token=abcdef1234567890...
```

### Step 3: Access the notebook
1. **Get the server's external IP address:**
   Ask Gemini:
   ```
   Show me the external IP address of the server.
   ```

2. **Construct the access URL:**
   Replace `0.0.0.0` with the external IP address in the Jupyter URL:
   ```
   http://EXTERNAL_IP:8888/?token=TOKEN
   ```

3. **Open in browser:**
   Paste this URL into your web browser to access the Jupyter notebook interface.

### Step 4: Verify GPU access
In Jupyter, create a new Julia notebook and run:

```julia
using CUDA
CUDA.versioninfo()
```

Expected output should show:
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

## Upload the tutorial notebook
1. In Jupyter, click **Upload** in the top right corner
2. Select the `Julia_demo.ipynb` file from your local machine
3. Click **Upload** to confirm
4. Open the uploaded notebook to begin the ocean modeling tutorial

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
