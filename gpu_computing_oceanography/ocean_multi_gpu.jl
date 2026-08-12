using CUDA
using MPI
MPI.Init()
const comm = MPI.COMM_WORLD
const rank = MPI.Comm_rank(comm)
const nranks = MPI.Comm_size(comm)
CUDA.device!(rank)

using Pkg; Pkg.activate("."); Pkg.instantiate()
using Printf, Statistics, FileIO, JLD2
using Reactant, Enzyme, CUDA
using Oceananigans, Oceananigans.Units, Oceananigans.DistributedComputations
using Oceananigans.Architectures: ReactantState
using SeawaterPolynomials, ClimaOcean.Diagnostics: MixedLayerDepthField, CairoMakie

include("ocean_utils.jl")
Oceananigans.defaults.FloatType = Float64

const Ntimesteps = 25; const Nspinup = 25
const Nx = 32; const Ny = 64; const Nz = 16
const Lx = 1e6; const Ly = 2e6

k_center = collect(1:Nz); \u0394z_center = @. 10 * 1.104^(Nz - k_center)
const Lz = sum(\u0394z_center); z_faces = vcat([-Lz], -Lz .+ cumsum(\u0394z_center)); z_faces[Nz+1] = 0
\u0394z = reshape(z_faces[2:end] - z_faces[1:end-1], 1, :)

parameters = (Ly=Ly, Lz=Lz, \u0394T=8, h=1000.0, y_sponge=1.9e6, \u03bbt=7days, \u03bc=1/30days, Lx=Lx, Nz=Nz)

# ... [Forward and Adjoint Wrappers same as previous script] ...

partition = Partition(x=2, y=2)
architecture = Distributed(ReactantState(), devices=(0, 1, 2, 3), partition=partition)

if rank == 0; @info "Launching 4-GPU Simulation on $(nranks) ranks..."; end
grid  = make_grid(architecture, Nx, Ny, Nz, Lx, Ly, Lz, z_faces, 4)
model = build_model(grid, 2.5minutes, parameters)
# [ ... simulation logic ... ]
MPI.Finalize()
