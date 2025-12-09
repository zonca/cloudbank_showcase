# 1 - Deploy JupyterHub with the Zero to JupyterHub chart

Goal: install JupyterHub on the GKE Autopilot cluster created in step 0, using the official Helm chart from the Zero to JupyterHub project.

## Prerequisites
- The `toy-hydro-cluster` from step 0 is Running.
- Cloud Shell is open (top bar **Activate Cloud Shell** icon) and connected to the cluster:
  ```bash
  kubectl config current-context
  ```
  Expect a value like `gke_<project>_us-west1_toy-hydro-cluster`. Autopilot spins nodes up only when workloads are scheduled.
- `kubectl` and `helm` are available in Cloud Shell (preinstalled).

Tip: Cloud Shell includes Gemini; you can ask it to run `gcloud`, `kubectl`, and `helm` commands for you and to interpret their output if anything fails.

## Install JupyterHub
1) Create a namespace and add the Helm repo:
   ```bash
   kubectl create namespace jhub
   helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
   helm repo update
   ```
2) Create a minimal config file for a small demo deployment (replace `your-admin-user` and a strong temporary password):
   ```bash
   cat <<'EOF' > jhub-config.yaml
   proxy:
     service:
       type: LoadBalancer

   hub:
     config:
       JupyterHub:
         admin_users:
           - your-admin-user

   auth:
     type: dummy
     dummy:
       password: "set-a-strong-temp-password"

   singleuser:
     image:
       name: jupyter/datascience-notebook
       tag: latest
     storage:
       capacity: 10Gi
   EOF
   ```
   Dummy authentication is only for this tutorial; change it before exposing to real users.

   **GitHub sign-in (optional)**  
   If you prefer GitHub authentication, create a GitHub OAuth app (Settings ▸ Developer settings ▸ OAuth Apps) with:
   - Homepage URL: `http://<EXTERNAL-IP>/`
   - Authorization callback URL: `http://<EXTERNAL-IP>/hub/oauth_callback`
   (If you want to avoid DNS setup, you can use a wildcard like `http://<EXTERNAL-IP>.nip.io/` for both fields, which resolves to the same IP.)

   Then use this values file instead of the dummy auth section above:
   ```bash
   cat <<'EOF' > jhub-config.yaml
   proxy:
     service:
       type: LoadBalancer

   hub:
     config:
       JupyterHub:
         admin_users:
           - your-admin-user

   auth:
     type: github
     github:
       clientId: "<github-client-id>"
       clientSecret: "<github-client-secret>"
       callbackUrl: "http://<EXTERNAL-IP>/hub/oauth_callback"

   singleuser:
     image:
       name: jupyter/datascience-notebook
       tag: latest
     storage:
       capacity: 10Gi
   EOF
   ```
   Replace `<EXTERNAL-IP>` with the load balancer IP (or `<EXTERNAL-IP>.nip.io` if you used that). Keep the admin user list and ensure you protect the client secret (do not commit it).
3) Install or upgrade the release (this pulls the latest chart):
   ```bash
   helm upgrade --install jhub jupyterhub/jupyterhub \
     --namespace jhub \
     --values jhub-config.yaml
   ```
4) Watch the pods until everything is Ready (Autopilot may need a few minutes to add nodes):
   ```bash
   kubectl -n jhub get pods -w
   ```

## Access JupyterHub
1) Find the external IP of the load balancer:
   ```bash
   kubectl -n jhub get svc proxy-public
   ```
   Sample output once the IP is assigned:
   ```
   NAME           TYPE           CLUSTER-IP    EXTERNAL-IP    PORT(S)        AGE
   proxy-public   LoadBalancer   10.0.32.123   34.82.10.20    80:30590/TCP   2m
   ```
2) Open `http://<EXTERNAL-IP>/` in your browser. Sign in with any username and the password you set in `jhub-config.yaml` (the admin username you listed will have admin rights inside JupyterHub).

## Clean up (optional)
To remove the demo deployment:
```bash
helm uninstall jhub -n jhub
kubectl delete namespace jhub
```
