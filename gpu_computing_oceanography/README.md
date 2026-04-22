# 🌊 GPU Computing in Oceanography on Google Cloud

This showcase demonstrates the power of GPU-accelerated, differentiable ocean modeling using Julia. By leveraging **Reactant.jl (XLA)** and **Enzyme.jl (Automatic Differentiation)**, we can simulate complex ocean dynamics and calculate sensitivities with unprecedented speed.

## 📁 Showcase Structure

The tutorial is divided into two main tracks:

### 1. Interactive Exploration (Single GPU)
Learn the fundamentals of differentiable oceanography in an interactive Jupyter environment.
*   **Main File:** [ocean_gpu_tutorial.ipynb](ocean_gpu_tutorial.ipynb)
*   **Key Concepts:** Ocean physics, topography (ridges), and calculating cause-and-effect (adjoint gradients).
*   **Setup Guides:**
    *   [1 - Create a GPU Instance](1_create_gpu_instance.md)
    *   [2 - Access via Browser](2_access_jupyter_browser.md)
    *   [3 - Access via VS Code](3_access_jupyter_vscode.md)

### 2. High-Performance Scaling (4-GPU Distributed)
Scale your simulation across multiple GPUs using MPI and XLA-distributed computing.
*   **Main File:** [ocean_multi_gpu.jl](ocean_multi_gpu.jl)
*   **Key Concepts:** Horizontal domain partitioning, MPI rank coordination, and headless visualization.
*   **Setup Guides:**
    *   [4 - Create a 4-GPU Instance](4_create_multi_gpu_instance.md)
    *   [5 - Run the Multi-GPU Simulation](5_run_multi_gpu_simulation.md)

---

## 🚀 Getting Started

If you are new to this showcase, start with **[Step 1: Create a GPU Instance](1_create_gpu_instance.md)** to set up your environment on Google Cloud.
