# 5 - Run the Multi-GPU Simulation with MPI

Goal: Configure the environment and launch a distributed 4-GPU ocean simulation across the 4 NVIDIA Tesla T4 GPUs on your instance.

## 1. Setting up the Multi-GPU VM Environment

Once your VM is created and running, you need to verify the GPU status and install the Julia simulation stack.

### SSH into the VM
Use the following command to connect to your 4-GPU instance:

\`\`\`bash
gcloud compute ssh julia-ocean-4gpu --zone=us-west1-b
\`\`\`

### Verify GPU Driver Installation
Verify the driver installation with:

\`\`\`bash
nvidia-smi
\`\`\`

**Expected Output:** You should see a table listing **4 NVIDIA Tesla T4** GPUs. If it says \`command not found\`, wait a few more minutes for the startup script to finish.

### Install Julia and the Simulation Stack
Run the following commands inside the VM to install Julia and the required packages:

\`\`\`bash
# Install Juliaup and Julia 1.11
curl -fsSL https://install.julialang.org | sh -s -- --yes
source ~/.bashrc
juliaup add 1.11
juliaup default 1.11

# Clone the showcase repository
git clone https://github.com/cloudbank/cloudbank_showcase.git
cd cloudbank_showcase/gpu_computing_oceanography/

# Instantiate the environment (this may take 5-10 minutes)
julia --project -e 'using Pkg; Pkg.instantiate()'
\`\`\`

---

## 2. Launching the 4-GPU Simulation

Standalone distributed simulations are run as Julia scripts using **MPI** (Message Passing Interface). We have provided a script, \`ocean_multi_gpu.jl\`, pre-configured for a **4-GPU (2x2)** horizontal partition, leveraging the shared logic in `ocean_utils.jl`.

Execute the following command to launch the simulation:

\`\`\`bash
mpiexec -n 4 julia --project ocean_multi_gpu.jl
\`\`\`

### How it works:
- **\`mpiexec -n 4\`**: Tells the system to launch 4 parallel instances of Julia.
- **\`Distributed(ReactantState(), ...)\`**: Coordinates communication between these 4 instances, ensuring each processes its own quadrant of the ocean while sharing data at the boundaries.
- **XLA & Reactant**: Each process compiles its part of the simulation into optimized machine code, fully leveraging the power of its assigned GPU.

---

## 3. Viewing the Results

The simulation is configured to save all visualizations as PNG files in the current directory:

- **\`ocean_state.png\`**: Visualizes temperature, sea surface height, and current velocities.
- **\`temperature_sensitivity.png\`**: Shows the adjoint sensitivity to initial temperature.
- **\`eddy_velocities.png\`**: High-resolution view of turbulent eddies.
- **\`wind_ssh_sensitivity.png\`**: Sensitivity to wind stress changes.

You can view these files by downloading them or using VS Code's built-in image viewer.
