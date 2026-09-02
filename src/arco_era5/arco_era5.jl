
# ECMWF's own ARCO Zarr access for ERA5/ERA5-Land, at
# arco.datastores.ecmwf.int -- gated by the same CDS API key as
# `CDSERA5`/`CDSERA5Land`, but authenticated HTTPS with no job queue. Each
# dataset splits into several topic-group Zarr stores, so `layers(T)` here
# means "topic group" (several variables each), not a single variable.

# Full URL metadata per group in one table (not derived from the Symbol via
# string replace) -- bucket ids and the exact hyphenated path segment are
# externally-controlled service details, confirmed against
# ecmwf-training/dss-notebooks and the CDS dataset pages.
const ECMWF_ERA5_GROUPS = (
    sfc = (path = "sfc", geo = 2, time = 2),
    wav = (path = "wav", geo = 3, time = 3),
)
const ECMWF_ERA5_LAND_GROUPS = (
    sfc_2m_temperature         = (path = "sfc-2m-temperature",         geo = 7,  time = 7),
    sfc_soil_temperature       = (path = "sfc-soil-temperature",       geo = 6,  time = 6),
    sfc_soil_water             = (path = "sfc-soil-water",             geo = 5,  time = 5),
    sfc_radiation_heat         = (path = "sfc-radiation-heat",         geo = 10, time = 10),
    sfc_snow                   = (path = "sfc-snow",                   geo = 30, time = 30),
    sfc_wind                   = (path = "sfc-wind",                   geo = 8,  time = 8),
    sfc_pressure_precipitation = (path = "sfc-pressure-precipitation", geo = 9,  time = 9),
    sfc_skin_temperature       = (path = "sfc-skin-temperature",       geo = 43, time = 43),
)

"""
    CDSZarrSource

Reference to an ECMWF ARCO Zarr store gated by a CDS API key, with a local
cache directory. Returned by `getraster` for [`ECMWFERA5`](@ref)/
[`ECMWFERA5Land`](@ref); open with `RasterDataSources.open_zarr_store`.

Carries no credential -- the token is resolved lazily inside
`open_zarr_store`, not stored here, so it's never on a struct that could be
printed or logged.
"""
struct CDSZarrSource
    url::String
    cache::String
end

@doc """
    ECMWFERA5 <: RasterDataSource

ERA5 (the reanalysis behind [`ERA5`](@ref) and [`CDSERA5`](@ref)), accessed
as an ARCO Zarr store hosted directly by ECMWF at
`arco.datastores.ecmwf.int`: gated by a CDS API key, read over
authenticated HTTPS, **no job queue** (unlike [`CDSERA5`](@ref)). An ARCO
*representation* of the dataset -- not guaranteed byte-identical to a
direct CDS download.

!!! warning
    CDS describes ARCO access as a **beta service** that may be modified or
    closed. Licence: CC-BY.

# Which ERA5 source do I want?
- [`ERA5`](@ref): public, no CDS account, whole global archive, browse lazily.
- `ECMWFERA5`/[`ECMWFERA5Land`](@ref): needs a CDS key, lazy, queue-free.
- [`CDSERA5`](@ref)/[`CDSERA5Land`](@ref): needs a CDS key, slower (job
    queue), returns a ready-to-use local NetCDF file.

# Setup
Same as [`CDSERA5`](@ref) -- see `RasterDataSources._cds_credentials`.

# Usage with `getraster`
    getraster(T::Type{ECMWFERA5}, [layer]; chunking=:geo)

# Arguments
- `layer`: a `Symbol` naming a **topic group** (several variables each, not
    one) -- `$(keys(ECMWF_ERA5_GROUPS))`. Required; no "all layers" default.

# Keywords
- `chunking`: `:geo` (default, small area/long time) or `:time` (large
    area/short time).

# Return value
`getraster` returns a `CDSZarrSource` reference, not a download. Open with
`RasterDataSources.open_zarr_store(source)` (needs `using Zarr` loaded).
Gives a raw Zarr group indexed by variable name/array position -- not a
`Rasters.jl` object with named selectors.

# Example
```julia
using RasterDataSources, Zarr
source = getraster(ECMWFERA5, :sfc)
ds = RasterDataSources.open_zarr_store(source)
keys(ds.arrays)  # list the variables in this group
```
""" ECMWFERA5
struct ECMWFERA5 <: RasterDataSource end

@doc """
    ECMWFERA5Land <: RasterDataSource

ERA5-Land, the land-only, higher-resolution companion to ERA5, as an
ECMWF-hosted ARCO Zarr store. See [`ECMWFERA5`](@ref) for full details --
everything there applies here except the dataset id and `layer` groups:
`$(keys(ECMWF_ERA5_LAND_GROUPS))`.

# Example
```julia
using RasterDataSources, Zarr
source = getraster(ECMWFERA5Land, :sfc_2m_temperature)
ds = RasterDataSources.open_zarr_store(source)
keys(ds.arrays)  # list the variables in this group
```
""" ECMWFERA5Land
struct ECMWFERA5Land <: RasterDataSource end

_arco_groups(::Type{ECMWFERA5}) = ECMWF_ERA5_GROUPS
_arco_groups(::Type{ECMWFERA5Land}) = ECMWF_ERA5_LAND_GROUPS
_arco_dataset_path(::Type{ECMWFERA5}) = "reanalysis_era5_single_levels"
_arco_dataset_path(::Type{ECMWFERA5Land}) = "reanalysis_era5_land"

layers(T::Type{<:Union{ECMWFERA5,ECMWFERA5Land}}) = keys(_arco_groups(T))
getraster_keywords(::Type{<:Union{ECMWFERA5,ECMWFERA5Land}}) = (:chunking,)

function _arco_group_url(T::Type{<:Union{ECMWFERA5,ECMWFERA5Land}}, layer::Symbol; chunking::Symbol=:geo)
    chunking in (:geo, :time) || throw(ArgumentError("chunking must be :geo or :time, got $chunking"))
    group = _arco_groups(T)[layer]
    bucket = getproperty(group, chunking)
    URI(scheme="https", host="arco.datastores.ecmwf.int",
        path="/cadl-arco-$chunking-$(lpad(bucket, 3, '0'))/arco/$(_arco_dataset_path(T))/$(group.path)/$(chunking)Chunked.zarr")
end

rasterpath(::Type{ECMWFERA5}) = joinpath(rasterpath(), "ECMWF-ARCO-ERA5")
rasterpath(::Type{ECMWFERA5Land}) = joinpath(rasterpath(), "ECMWF-ARCO-ERA5-Land")
# `chunking` is part of the cache path -- the geo- and time-chunked stores
# for the same group are different remote data and must not share a
# directory.
rasterpath(T::Type{<:Union{ECMWFERA5,ECMWFERA5Land}}, layer::Symbol; chunking::Symbol=:geo) =
    joinpath(rasterpath(T), string(layer), string(chunking))

getraster(T::Type{<:Union{ECMWFERA5,ECMWFERA5Land}}, layers::Union{Tuple,Symbol}; chunking::Symbol=:geo) =
    _getraster(T, layers, chunking)
_getraster(T::Type{<:Union{ECMWFERA5,ECMWFERA5Land}}, layers::Tuple, chunking) = _map_layers(T, layers, chunking)
function _getraster(T::Type{<:Union{ECMWFERA5,ECMWFERA5Land}}, layer::Symbol, chunking)
    _check_layer(T, layer)
    cache = rasterpath(T, layer; chunking)
    mkpath(cache)
    CDSZarrSource(string(_arco_group_url(T, layer; chunking)), cache)
end

"""
    open_zarr_store(source::CDSZarrSource)

Open an [`ECMWFERA5`](@ref)/[`ECMWFERA5Land`](@ref) Zarr store reference,
returning a raw Zarr group. Requires `using Zarr` loaded first -- the only
method lives in the `RasterDataSourcesZarrExt` extension (declared here
with no body, since Julia disallows an extension overwriting a method with
the same signature during precompilation); without `Zarr` loaded, calling
this raises a `MethodError` rather than an `UndefVarError`.
"""
function open_zarr_store end
