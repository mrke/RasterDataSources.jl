
# ECMWF's own ARCO Zarr access for ERA5/ERA5-Land at
# arco.datastores.ecmwf.int -- gated by the same CDS API key as
# `ERA5CDS`/`ERA5CDSLand`, but authenticated HTTPS with no job queue. Each
# dataset splits into several topic-group Zarr stores, so `layers(T)` here
# means "topic group" (several variables each), not a single variable.

# Bucket id + path segment per group; externally-controlled service details.
# One bucket per group -- geo- and time-chunked layouts share the same id.
const ECMWF_ERA5_GROUPS = (
    sfc = (path = "sfc", bucket = 2),
    wav = (path = "wav", bucket = 3),
)
const ECMWF_ERA5_LAND_GROUPS = (
    sfc_2m_temperature         = (path = "sfc-2m-temperature",         bucket = 7),
    sfc_soil_temperature       = (path = "sfc-soil-temperature",       bucket = 6),
    sfc_soil_water             = (path = "sfc-soil-water",             bucket = 5),
    sfc_radiation_heat         = (path = "sfc-radiation-heat",         bucket = 10),
    sfc_snow                   = (path = "sfc-snow",                   bucket = 30),
    sfc_wind                   = (path = "sfc-wind",                   bucket = 8),
    sfc_pressure_precipitation = (path = "sfc-pressure-precipitation", bucket = 9),
    sfc_skin_temperature       = (path = "sfc-skin-temperature",       bucket = 43),
)

abstract type AbstractERA5ECMWF <: RasterDataSource end

@doc """
    ERA5ECMWF <: RasterDataSource

ERA5 (also behind [`ERA5`](@ref) and [`ERA5CDS`](@ref)), as an ARCO Zarr
store hosted by ECMWF: gated by a CDS API key, no job queue (unlike
[`ERA5CDS`](@ref)). An ARCO *representation* -- not guaranteed
byte-identical to a CDS download.

!!! warning
    ECMWF/CDS describe ARCO access as a **beta service**. Licence: CC-BY.

Needs a CDS API key -- see `RasterDataSources._cds_credentials`.

# Usage with `getraster`
    getraster(T::Type{ERA5ECMWF}, layer; chunking=:geo)

# Arguments
- `layer`: a `Symbol` naming a topic group (several variables each) --
    `$(keys(ECMWF_ERA5_GROUPS))`. Required; no "all layers" default.

# Keywords
- `chunking`: `:geo` (default, small area/long time) or `:time` (large
    area/short time).

Returns a `CDSZarrSource` reference, not a download -- open with
`RasterDataSources.open_zarr_store(source)` (needs `using Zarr`), giving a
raw Zarr group, not a `Rasters.jl` object.

# Example
```julia
using RasterDataSources, Zarr
source = getraster(ERA5ECMWF, :sfc)
ds = RasterDataSources.open_zarr_store(source)
keys(ds.arrays)  # list the variables in this group
```
""" ERA5ECMWF
struct ERA5ECMWF <: AbstractERA5ECMWF end

@doc """
    ERA5ECMWFLand <: RasterDataSource

ERA5-Land, the land-only, higher-resolution companion to ERA5, as an
ECMWF-hosted ARCO Zarr store. See [`ERA5ECMWF`](@ref) for setup and usage --
the only difference here is the `layer` groups: `$(keys(ECMWF_ERA5_LAND_GROUPS))`.

# Example
```julia
using RasterDataSources, Zarr
source = getraster(ERA5ECMWFLand, :sfc_2m_temperature)
ds = RasterDataSources.open_zarr_store(source)
keys(ds.arrays)  # list the variables in this group
```
""" ERA5ECMWFLand
struct ERA5ECMWFLand <: AbstractERA5ECMWF end

# `_ecmwf_arco_*` names disambiguate from `era5.jl`'s unrelated GCP ARCO-ERA5 source.
_ecmwf_arco_groups(::Type{ERA5ECMWF}) = ECMWF_ERA5_GROUPS
_ecmwf_arco_groups(::Type{ERA5ECMWFLand}) = ECMWF_ERA5_LAND_GROUPS
_ecmwf_arco_dataset_path(::Type{ERA5ECMWF}) = "reanalysis_era5_single_levels"
_ecmwf_arco_dataset_path(::Type{ERA5ECMWFLand}) = "reanalysis_era5_land"

layers(T::Type{<:AbstractERA5ECMWF}) = keys(_ecmwf_arco_groups(T))
getraster_keywords(::Type{<:AbstractERA5ECMWF}) = (:chunking,)

# `layer` here is a topic group (e.g. `:sfc`), not an individual variable array.
layername(::Type{<:AbstractERA5ECMWF}, layer::Symbol) = string(layer)

_check_arco_chunking(chunking::Symbol) =
    chunking in (:geo, :time) || throw(ArgumentError("chunking must be :geo or :time, got $chunking"))

function _ecmwf_arco_group_url(T::Type{<:AbstractERA5ECMWF}, layer::Symbol; chunking::Symbol=:geo)
    group = _ecmwf_arco_groups(T)[layer]
    URI(scheme="https", host="arco.datastores.ecmwf.int",
        path="/cadl-arco-$chunking-$(lpad(group.bucket, 3, '0'))/arco/$(_ecmwf_arco_dataset_path(T))/$(group.path)/$(chunking)Chunked.zarr")
end

rasterpath(::Type{ERA5ECMWF}) = joinpath(rasterpath(), "ECMWF-ARCO-ERA5")
rasterpath(::Type{ERA5ECMWFLand}) = joinpath(rasterpath(), "ECMWF-ARCO-ERA5-Land")
# geo- and time-chunked stores for the same group are different remote data.
rasterpath(T::Type{<:AbstractERA5ECMWF}, layer::Symbol; chunking::Symbol=:geo) =
    joinpath(rasterpath(T), string(layer), string(chunking))

# No "all layers" default -- unlike the generic `getraster(T; kw...)`
# fallback, a topic group must always be specified.
getraster(T::Type{<:AbstractERA5ECMWF}; kw...) = throw(ArgumentError(
    "a topic group must be specified, e.g. getraster($T, :sfc); valid groups are $(layers(T))"
))
getraster(T::Type{<:AbstractERA5ECMWF}, layers::Union{Tuple,Symbol}; chunking::Symbol=:geo) =
    (_check_arco_chunking(chunking); _getraster(T, layers, chunking))
_getraster(T::Type{<:AbstractERA5ECMWF}, layers::Tuple, chunking) = _map_layers(T, layers, chunking)
function _getraster(T::Type{<:AbstractERA5ECMWF}, layer::Symbol, chunking)
    _check_layer(T, layer)
    # No `mkpath` here -- `getraster` only builds a reference; `Zarr.DirectoryStore`
    # creates the cache directory itself when the store is actually opened.
    CDSZarrSource(string(_ecmwf_arco_group_url(T, layer; chunking)), rasterpath(T, layer; chunking))
end
