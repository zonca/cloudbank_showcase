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
2) Create a minimal config file for a small demo deployment. Use your current shell user as admin, allow only that user to log in, and generate a temporary password on the fly. Important: the final `EOF` line must start at column 1 (no spaces) or the shell will keep showing `>` waiting for input.
```bash
export JHUB_ADMIN="${USER}"
export JHUB_PASS="$(openssl rand -base64 20)"
cat > jhub-config.yaml <<EOF
proxy:
  service:
    type: LoadBalancer

hub:
  config:
    Authenticator:
      admin_users:
        - ${JHUB_ADMIN}
      allowed_users:
        - ${JHUB_ADMIN}
    DummyAuthenticator:
      password: "${JHUB_PASS}"

singleuser:
  image:
    name: quay.io/jupyter/scipy-notebook
    tag: latest
  storage:
    capacity: 10Gi
  cloudMetadata:
    blockWithIptables: false
  networkPolicy:
    egress:
      - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: portal
  networkPolicy:
    egress:
      - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: portal

scheduling:
  userScheduler:
    enabled: false
  podPriority:
    enabled: true

prePuller:
  hook:
    enabled: false
EOF
```
Notes:
- Only the user listed in `admin_users` / `allowed_users` can log in. Update those lists if you need others.
- `userScheduler.enabled: false` is required because GKE Autopilot forbids custom schedulers; we must use the default GKE scheduler.
- `cloudMetadata.blockWithIptables: false` is required because Autopilot disallows pods that add NET_ADMIN/iptables rules; leaving it `true` would be rejected by Autopilot’s security controls.
- `networkPolicy.egress` allows the singleuser servers to reach the `portal` namespace (needed for the portal service).
- `podPriority.enabled: true` lets the chart set higher priority for the hub pods, while disabling the `prePuller.hook` avoids the failing image-puller hook (the chart expected a `jhub-image-puller-priority` class that was not present). The hook only pre-pulls images for speed, so turning it off is safe.
Dummy authentication is only for this tutorial; change it before exposing to real users. The password generated above is available in `JHUB_PASS` for the session.

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
2) Open `http://<EXTERNAL-IP>/` in your browser. To remember the credentials you generated earlier, print them in Cloud Shell:
   ```bash
   echo "User: ${JHUB_ADMIN}"
   echo "Pass: ${JHUB_PASS}"
   ```
   Sign in with any username and that password (the admin username you listed will have admin rights inside JupyterHub).

### Optional: quick HTTPS with a self-signed cert
This adds TLS at the JupyterHub proxy. Browsers will warn about the certificate, but traffic is encrypted end-to-end.
```bash
# 1) Capture the load balancer IP and mint a short-lived cert for <IP>.nip.io
LB_IP="$(kubectl -n jhub get svc proxy-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
export JHUB_HOST="${LB_IP}.nip.io"
openssl req -x509 -nodes -newkey rsa:2048 -days 7 \
  -keyout tls.key -out tls.crt -subj "/CN=${JHUB_HOST}"

# 2) Store the cert as a TLS secret the chart can read
kubectl -n jhub delete secret jhub-selfsigned --ignore-not-found
kubectl -n jhub create secret tls jhub-selfsigned --key tls.key --cert tls.crt

# 3) Create a small overlay file enabling HTTPS and rerun Helm
cat > https-selfsigned.yaml <<EOF
proxy:
  https:
    enabled: true
    type: secret
    hosts:
      - ${JHUB_HOST}
    secret:
      name: jhub-selfsigned
EOF

helm upgrade --install jhub jupyterhub/jupyterhub \
  --namespace jhub \
  --values jhub-config.yaml \
  --values https-selfsigned.yaml

echo "Open: https://${JHUB_HOST}/"
```

## Clean up (optional)
To remove the demo deployment:
```bash
helm uninstall jhub -n jhub
kubectl delete namespace jhub
```
