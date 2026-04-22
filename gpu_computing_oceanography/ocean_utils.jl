using Oceananigans.Grids: ynode, znode
using Oceananigans.Architectures: ReactantState
using Oceananigans
using Oceananigans.Units
using Oceananigans.DistributedComputations
using SeawaterPolynomials
using ClimaOcean.Diagnostics: MixedLayerDepthField

# --- Physics Helper Functions ---

function ridge_function(x, y, Lz, Lx, Ly)
    zonal = (Lz+3000)exp(-(x - Lx/2)^2/(1e6kilometers))
    gap   = 1 - 0.5(tanh((y - (Ly/6))/1e5) - tanh((y - (Ly/2))/1e5))
    return zonal * gap - Lz
end

function make_grid(architecture, Nx, Ny, Nz, Lx, Ly, Lz, z_faces, halo_size)
    underlying_grid = RectilinearGrid(architecture,
        topology = (Periodic, Bounded, Bounded),
        size = (Nx, Ny, Nz),
        halo = (halo_size, halo_size, halo_size),
        x = (0, Lx), y = (0, Ly), z = z_faces)
    
    ridge = Field{Center, Center, Nothing}(underlying_grid)
    set!(ridge, (x, y) -> ridge_function(x, y, Lz, Lx, Ly))
    
    return ImmersedBoundaryGrid(underlying_grid, GridFittedBottom(ridge))
end

function build_model(grid, Δt₀, parameters)
    temperature_flux_bc = FluxBoundaryCondition(Field{Center, Center, Nothing}(grid))
    u_stress_bc = FluxBoundaryCondition(Field{Face, Center, Nothing}(grid))
    v_stress_bc = FluxBoundaryCondition(Field{Center, Face, Nothing}(grid))

    @inline u_drag(i, j, grid, clock, model_fields, p) = @inbounds -p.μ * p.Lz * model_fields.u[i, j, 1]
    @inline v_drag(i, j, grid, clock, model_fields, p) = @inbounds -p.μ * p.Lz * model_fields.v[i, j, 1]

    u_drag_bc = FluxBoundaryCondition(u_drag, discrete_form = true, parameters = parameters)
    v_drag_bc = FluxBoundaryCondition(v_drag, discrete_form = true, parameters = parameters)

    T_bcs = FieldBoundaryConditions(top = temperature_flux_bc)
    u_bcs = FieldBoundaryConditions(top = u_stress_bc, bottom = u_drag_bc)
    v_bcs = FieldBoundaryConditions(top = v_stress_bc, bottom = v_drag_bc)

    coriolis = BetaPlane(f₀ = -1e-4, β = 1e-11)

    @inline initial_temperature(z, p) = p.ΔT * (exp(z / p.h) - exp(-p.Lz / p.h)) / (1 - exp(-p.Lz / p.h))
    @inline mask(y, p)                = max(0.0, y - p.y_sponge) / (p.Ly - p.y_sponge)

    @inline function temperature_relaxation(i, j, k, grid, clock, model_fields, p)
        timescale = p.λt
        y = ynode(j, grid, Center())
        z = znode(k, grid, Center())
        target_T = initial_temperature(z, p)
        T = @inbounds model_fields.T[i, j, k]
        return -1 / timescale * mask(y, p) * (T - target_T)
    end
    
    FT = Forcing(temperature_relaxation, discrete_form = true, parameters = parameters)

    horizontal_closure = HorizontalScalarDiffusivity(ν = 500.0, κ = 5e-5)
    vertical_closure = VerticalScalarDiffusivity(ν = 3e-3, κ = 5e-5)

    model = HydrostaticFreeSurfaceModel(
        grid,
        free_surface = SplitExplicitFreeSurface(substeps=10),
        momentum_advection = WENO(order=3),
        tracer_advection = WENO(order=3),
        buoyancy = SeawaterBuoyancy(equation_of_state=LinearEquationOfState(Float64)),
        coriolis = coriolis,
        closure = (horizontal_closure, vertical_closure),
        tracers = (:T, :S, :e),
        boundary_conditions = (T = T_bcs, u = u_bcs, v = v_bcs),
        forcing = (T = FT,)
    )
    model.clock.last_Δt = Δt₀
    return model
end
