using CUDA
# ==============================================================================
# 🌊 MULTI-GPU OCEANOGRAPHY TUTORIAL: REENTRANT CHANNEL WITH ADJOINT SENSITIVITY
# ==============================================================================
# This script demonstrates how to scale a differentiable ocean model across 
# multiple GPUs using Reactant.jl (XLA), Enzyme.jl (AD), and MPI.
# ==============================================================================

# ------------------------------------------------------------------------------
# PHASE 1: MPI AND ENVIRONMENT INITIALIZATION
# ------------------------------------------------------------------------------
using MPI
MPI.Init()

using CUDA
const comm = MPI.COMM_WORLD
const rank = MPI.Comm_rank(comm)
# Force each rank to only see its assigned GPU
CUDA.device!(rank)


const nranks = MPI.Comm_size(comm)

# Ensure each MPI rank only sees ONE specific GPU
CUDA.device!(rank)

using Pkg
Pkg.activate(".")
Pkg.instantiate()

using Printf, Statistics, FileIO, JLD2
using Reactant, Enzyme, CUDA
using Oceananigans
using Oceananigans.Units
using Oceananigans.DistributedComputations
using Oceananigans.Architectures: ReactantState
using SeawaterPolynomials
using ClimaOcean.Diagnostics: MixedLayerDepthField
using CairoMakie

# Load shared physics functions from our helper file
include("ocean_utils.jl")

# Set default precision
Oceananigans.defaults.FloatType = Float64

# ------------------------------------------------------------------------------
# PHASE 2: MODEL PARAMETERS & GRID GEOMETRY
# ------------------------------------------------------------------------------
const Ntimesteps = 25
const Nspinup    = 25
const Nx = 32; const Ny = 64; const Nz = 16
const Lx = 1000kilometers; const Ly = 2000kilometers

k_center = collect(1:Nz)
Δz_center = @. 10 * 1.104^(Nz - k_center)
const Lz = sum(Δz_center)
z_faces = vcat([-Lz], -Lz .+ cumsum(Δz_center))
z_faces[Nz+1] = 0
Δz = reshape(z_faces[2:end] - z_faces[1:end-1], 1, :)

parameters = (
    Ly = Ly, Lz = Lz, ΔT = 8, h = 1000.0, y_sponge = 19/20 * Ly, λt = 7.0days,
    μ = 1 / 30days, Lx = Lx, Nz = Nz
)

# ------------------------------------------------------------------------------
# PHASE 3: DIFFERENTIABLE WRAPPERS
# ------------------------------------------------------------------------------

function spinup_reentrant_channel_model!(model, Δt, N)
    for i = 1:N
        time_step!(model, Δt)
    end
    return nothing
end

function estimate_tracer_error(model, Tᵢ, Sᵢ, u_wind_stress, v_wind_stress, temp_flux, Δz, mld)
    for i = 1:Ntimesteps
        time_step!(model, model.clock.last_Δt)
    end
    Nx, Ny, Nz = size(model.grid)
    zonal_transport = (model.velocities.u[Int(Nx/2)+1, 1:Ny, 1:Nz] .* model.grid.Δyᵃᶜᵃ) .* Δz
    return sum(zonal_transport) / 1e6
end

function differentiate_tracer_error(model, Tᵢ, Sᵢ, u_wind_stress, v_wind_stress, temp_flux, Δz, mld,
                                   dmodel, dTᵢ, dSᵢ, du_wind_stress, dv_wind_stress, dtemp_flux, dΔz, dmld)
    autodiff(set_strong_zero(Enzyme.ReverseWithPrimal),
             estimate_tracer_error, Active,
             Duplicated(model, dmodel), Duplicated(Tᵢ, dTᵢ), Duplicated(Sᵢ, dSᵢ),
             Duplicated(u_wind_stress, du_wind_stress), Duplicated(v_wind_stress, dv_wind_stress),
             Duplicated(temp_flux, dtemp_flux), Duplicated(Δz, dΔz), Duplicated(mld, dmld))
    return nothing
end

# ------------------------------------------------------------------------------
# PHASE 4: MULTI-GPU EXECUTION
# ------------------------------------------------------------------------------

# STEP 4.1: Define the Distributed Architecture (2x2 Grid = 4 GPUs)
partition = Partition(x=2, y=1)
architecture = ReactantState()

if rank == 0; @info "Launching 2-GPU Simulation on $(nranks) ranks..."; end

# STEP 4.2: Build Grid and Model (Using Helper Functions)
Δt₀ = 2.5minutes 
grid  = make_grid(architecture, Nx, Ny, Nz, Lx, Ly, Lz, z_faces, 4)
model = build_model(grid, Δt₀, parameters)

# Initial conditions
Tᵢ, Sᵢ = Field{Center, Center, Center}(grid), Field{Center, Center, Center}(grid)
set!(Tᵢ, 8.0); set!(Sᵢ, 35.0)
mld  = MixedLayerDepthField(model.buoyancy, grid, model.tracers)
Δz_reactant = Reactant.ConcreteRArray(Δz)

# STEP 4.3: Shadow variables for Enzyme
dmodel = Enzyme.make_zero(model)
dTᵢ = Field{Center, Center, Center}(grid)
du_wind_stress = Field{Face, Center, Nothing}(grid)

# STEP 4.4: Compilation & Execution
if rank == 0; @info "Compiling XLA kernels..."; end

rspinup = @compile spinup_reentrant_channel_model!(model, Δt₀, Nspinup)
rdiff = @compile differentiate_tracer_error(model, Tᵢ, Sᵢ, model.velocities.u.boundary_conditions.top.condition, 
                                            model.velocities.v.boundary_conditions.top.condition, 
                                            model.tracers.T.boundary_conditions.top.condition, Δz_reactant, mld, 
                                            dmodel, dTᵢ, Sᵢ, du_wind_stress, du_wind_stress, dTᵢ, Δz_reactant, mld)

if rank == 0; @info "Running Physics Spinup..."; end
rspinup(model, Δt₀, Nspinup)

if rank == 0; @info "Computing Adjoint Gradients..."; end
rdiff(model, Tᵢ, Sᵢ, model.velocities.u.boundary_conditions.top.condition, 
      model.velocities.v.boundary_conditions.top.condition, 
      model.tracers.T.boundary_conditions.top.condition, Δz_reactant, mld, 
      dmodel, dTᵢ, Sᵢ, du_wind_stress, du_wind_stress, dTᵢ, Δz_reactant, mld)

# ------------------------------------------------------------------------------
# PHASE 5: HEADLESS VISUALIZATION (RANK 0 ONLY)
# ------------------------------------------------------------------------------
if rank == 0
    @info "Simulation Complete. Saving visualizations to PNG..."

    fig1 = Figure(size = (1200, 800))
    ax1 = Axis(fig1[1, 1], title = "Surface Temperature (4-GPU Combined)")
    heatmap!(ax1, Array(interior(model.tracers.T, :, :, Nz)), colormap = :thermal)
    save("ocean_state.png", fig1)

    fig2 = Figure(size = (1200, 800))
    ax2 = Axis(fig2[1, 1], title = "Adjoint Sensitivity (dT/dJ)")
    heatmap!(ax2, Array(interior(dTᵢ, :, :, Nz)), colormap = :balance)
    save("temperature_sensitivity.png", fig2)

    @info "Images saved: ocean_state.png, temperature_sensitivity.png"
end

MPI.Finalize()
