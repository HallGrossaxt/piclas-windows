(sec:raytracing-photoionzation)=
# Raytracing & Photoionization

A ray tracing model is implemented in PICLas to be utilized with the photo-ionization module. A boundary must be defined from which rays or photons are emitted in a preliminary step, which are tracked throughout the domain until they are absorbed at a boundary. The volumes and surface elements are sampled by passing photons and from this information the ionization within each volume element and secondary electron emission from each surface is calculated in the actual plasma simulation. The output of the sampling procedure can be viewed as irradiated volumes and surfaces and is written to the output files ProjectName_RadiationVolState.h5 and ProjectName_RadiationSurfState.h5, which can be converted to .vtk format with piclas2vtk. The raytracing result can be precomputed and will be read-in if available in the simulation folder.

Raytracing is activated with

    UseRayTracing = T

The user must specify a single rectangular and planar particle-boundary in an xy-plane (here with index 5)

    RayTracing-PartBound = 5

from which the number of rays

    RayTracing-NumRays = 200000000

shall be emitted in the direction

    RayTracing-RayDirection = (/0.0, 0.0, -1.0/)

Currently, all coordinates of this boundary must have the same z-coordinate and it must extend into the complete domain into the x- and y-direction. The angle under which photons are emitted from the particle-boundary is calculated from the normal vector of the boundary and the direction vector given above.

## Pulse definition

Depending on the application different types of pulses can be defined to model different temporal photon behaviour. The number and type of the pulses can be defined with

    RayTracing-NbrOfPulses = 2
    RayTracing-PulseType = Gaussian

Currently, two options are available: constant and Gaussian (default). The parameter

    RayTracing-PulseDuration = 1e-9

defines the pulse duration $\tau$ in [s]. For a Gaussian-type, it describes the temporal shape of the light intensity function $I\propto\exp(-(t/\tau)^2)$. For a square-type, it corresponds to the power cycle duration. The power cycle duration for a Gaussian pulse is $2\sqrt{8}\tau$. The repetition rate $f$ of the pulses in [Hz], used to calculate the period, is given by

    RayTracing-RepetitionRate = 2e3

It should be noted that the power cycle duration for the Gaussian-type pulse must be less than the period (which is $1/f$). The time-averaged (over one pulse) power density of the pulse in [W/m2] is defined by

    RayTracing-PowerDensity = 1e3

which is converted to an intensity amplitude using the photon-emission area, pulse duration and repetition rate, depending on the pulse type. Finally, the wavelength in [m] defines the photon energy and is given by

    RayTracing-WaveLength = 50e-9

## Surface interaction

To account for the reflectivity of specific surfaces, the absorption rate $A_{\nu}=1-R$ ($R$ is the reflectivity) for photons must be supplied for each particle boundary. This is done by setting the parameter

    Part-Boundary1-PhotonEnACC = 1.0

to a value between zero and unity. Additionally, it is possibly to switch between perfect angular reflection and diffuse reflection for each boundary.

    Part-Boundary$-PhotonSpecularReflection = T

The parameter

    RayTracing-ForceAbsorption=T

activates sampling of photons on surfaces independent of what happens to them there. They might be reflected or absorbed. If this parameter is set to `false`, then only absorbed photons will be sampled on surfaces. By also sampling reflected photons, the statistic is improved, hence, it should always be activated.

It should be noted that the parameters that do not directly influence the raytracing result (e.g. repetition rate, power density, wave length etc.) can be changed between simulations and the raytracing result reused.

## Photo-ionization probability

The actual photo-ionization reactions have to be defined separately. The ionization reactions are defined as described in Section {ref}`sec:DSMC-chemistry` by

    DSMC-NumOfReactions = 1
    DSMC-Reaction1-ReactionType = phIon
    DSMC-Reaction1-Reactants    = (/3,0,0/)
    DSMC-Reaction1-Products     = (/1,2,0/)
    DSMC-Reaction1-CrossSection = 4.84E-24      ! [m^2]

The probability that an ionization event occurs is determined based on the given cross-section, which is usually given for a
certain wave length/photon energy. It should be noted that the background gas species should be given as the sole reactant and
electrons should be defined as the first and/or second product. Electrons will be emitted perpendicular to the light path defined
by the cylinder axis according to a cosine squared distribution.

## Volume and surface super-sampling

Because the interaction of every ray with every volume and surface element in three dimensions would lead to an unfeasible amount of memory usage if stored on the hard drive, the calculated volume and surface intersections need to be agglomerated in such a way that the details of the irradiated geometry are preserved. One goal is to have a clean cut between shadowed and illuminated regions where this interface cuts through surface of volume elements and without the need for a cut-cell method that splits the actual mesh elements. This is achieved by introducing a super-sampling method in the volume as well as on the surface elements. For the volumetric sampling, the originally cell-constant value is distributed among the volume sub-cells depending on a element-specific number of sub cells $n_{cells} = (N_{cell} + 1)^3$ , where
$N_{cell}$ is the polynomial degree in each element used for visualization of the super-sampled
ray tracing solution. The polynomial degree $N_{cell}$ is chosen between unity and a user-defined
value, which can be automatically selected depending on the different criteria

    RayTracing-VolRefineMode = 0 ! 0: do nothing (default)
                                 ! 1: refine below user-defined z-coordinate with NMax
                                 ! 2: scale N according to the mesh element volume between NMin>=1 and NMax>=2
                                 ! 3: refine below user-defined z-coordinate and scale N according to the mesh element volume between NMin>=1 and NMax>=2 (consider only elements below the user-defined z-coordinate for the scaling)

The maximum polynomial degree within refined volume elements for photon tracking (p-adaption) can hereby be set using

    RayTracing-NMax = 1

In contrast to the volume super-sampling, only one global parameter is used to refine the all surfaces for sampling. Each surface can be split into $n^2$ sub-surfaces on which the sampling is performed via the parameter

    RayTracing-nSurfSample = 2

The surfaces (quadrilaterals) are therefore equidistantly divided at the midpoint of each edge to create approximately equal-sized sub-surfaces.