# 4 - Create a 4-GPU Instance on Google Cloud

Goal: Create a powerful multi-GPU virtual machine instance on Google Cloud Platform to run distributed Julia ocean modeling simulations.

## Prerequisites
- Authenticated \`gcloud\` CLI.
- Sufficient GPU quota in your chosen region.

## 1. Local Google Cloud Authentication

To manage multiple GPU instances from your terminal, you must first authenticate your local \`gcloud\` CLI.

Run the following command in your terminal:

\`\`\`bash
gcloud auth login
\`\`\`

1.  A browser window will open.
2.  Sign in with your Google Cloud credentials.
3.  Once completed, your terminal is authorized to interact with your cloud project.

Verify your active project:

\`\`\`bash
gcloud config set project access-20251001-zonca-473937
\`\`\`

---

## 2. Create the 4-GPU VM Instance 

Use the following command to create a single VM with 4 Tesla T4 GPUs. This configuration provides the 16 vCPUs and 60GB of RAM necessary to handle the overhead of a 4-GPU distributed simulation.

\`\`\`bash 
gcloud compute instances create julia-ocean-4gpu \
    --zone=us-west1-b \
    --machine-type=n1-standard-64 \
    --accelerator=type=nvidia-tesla-t4,count=4 \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=200GB \
    --boot-disk-type=pd-ssd \
    --maintenance-policy=TERMINATE \
    --metadata="install-nvidia-driver=true" 
\`\`\` 

### Monitoring Initialization
The VM will automatically install the NVIDIA drivers (v535) upon creation. This process usually takes **5-8 minutes**. You can proceed to the next tutorial once the instance status is \`RUNNING\`.
