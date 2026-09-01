const ACCESSS_LAYERS = (
    rain = (description="Daily rainfall",              units="mm"),
    tmax = (description="Maximum daily temperature",   units="°C"),
    tmin = (description="Minimum daily temperature",   units="°C"),
    radn = (description="Daily global solar radiation", units="MJ/m^2"),
    evap = (description="Daily evaporation",            units="mm"),
    vapr = (description="Vapour pressure",              units="hPa"),
)

const ACCESSS_BASE_URI = URI(scheme="https", host="senaps.net",
    path="/thredds/fileServer/org_catalogs/csiro-dews/DEWS/access_s_downscaled_silo")

@doc """
    ACCESSS <: RasterDataSource

Data from ACCESS-S2 (Australian Community Climate and Earth-System Simulator
-- Seasonal), the Bureau of Meteorology's weekly-to-seasonal ensemble forecast
system, downscaled to SILO's ~5 km Australian grid.

See: [CSIRO -- ACCESS-S climate forecast system](http://www.csiro.au)

Data are served as one NetCDF file per variable per forecast issue date, from
a THREDDS server at `senaps.net`. Each file spans the full forecast period
from its issue date and carries `lon`/`lat`/`time` dimensions plus a 99-member
`ensemble` dimension (all ensemble members are included in the one file --
`getraster` has no way to download a subset of them).

# Usage with `getraster`
    getraster(source::Type{ACCESSS}, [layer]; date)

# Arguments
- `layer`: `Symbol` or `Tuple` of `Symbol` from `$(keys(ACCESSS_LAYERS))`.
    Without a `layer` argument all layers are downloaded and a `NamedTuple`
    of paths returned.

# Keywords
- `date`: a `Date` giving the forecast issue date (e.g. `Date(2026, 7, 1)`
    for the `20260701` issue). For multiple dates, a `Vector` of paths is
    returned.

# Example
```julia
julia> getraster(ACCESSS, :tmax; date=Date(2026, 7, 1))
"/path/to/storage/ACCESS-S2/tmax/20260701_tmax.nc"
```

Returns the filepath/s of the downloaded or pre-existing files. Files are
large (several GB each -- all ensemble members and the full forecast period
in one download); there is currently no point-native (`PointDataSources.jl`)
or spatial-subsetting access for this source.

!!! warning
    Two things about this source are unverified:
    1. The base URL was inferred from a single THREDDS catalog page/Siphon
       notebook for one issue date (`20260701`) -- it hasn't been confirmed
       against a second issue date.
    2. The dataset reports `restrictAccess: csiro-dews:dews` on its THREDDS
       catalog entry, meaning access may be credentialed. `getraster` here
       makes a plain unauthenticated request, matching every other source in
       this package; if that 401s/403s, the request will need whatever
       credential scheme `csiro-dews:dews` actually requires (unknown at the
       time this source was written).
    3. This is the real-time forecast archive only. The separate 1981-2018
       ACCESS-S2 hindcast archive is hosted at NCI, under a different URL
       entirely -- not covered by this source.
""" ACCESSS
struct ACCESSS <: RasterDataSource end

layers(::Type{ACCESSS}) = keys(ACCESSS_LAYERS)
date_step(::Type{ACCESSS}) = Month(1)
date_range(::Type{ACCESSS}) = (Date(2018, 1, 1), Date(year(today()), 12, 31))
getraster_keywords(::Type{ACCESSS}) = (:date,)

rastername(::Type{ACCESSS}, layer::Symbol; date) =
    "$(Dates.format(date, "yyyymmdd"))_$(layer).nc"

rasterpath(::Type{ACCESSS}) = joinpath(rasterpath(), "ACCESS-S2")
rasterpath(T::Type{ACCESSS}, layer::Symbol; date) =
    joinpath(rasterpath(T), string(layer), rastername(T, layer; date))

rasterurl(T::Type{ACCESSS}, layer::Symbol; date) =
    joinpath(ACCESSS_BASE_URI, Dates.format(date, "yyyymmdd"), rastername(T, layer; date))

function getraster(T::Type{ACCESSS}, layers::Union{Tuple,Symbol}; date)
    _getraster(T, layers, date)
end

function _getraster(T::Type{ACCESSS}, layers, dates::Tuple{<:Any,<:Any})
    _getraster(T, layers, date_sequence(T, dates))
end
function _getraster(T::Type{ACCESSS}, layers, dates::AbstractArray)
    _getraster.(T, Ref(layers), dates)
end
function _getraster(T::Type{ACCESSS}, layers::Tuple, date::Dates.TimeType)
    _map_layers(T, layers, date)
end
function _getraster(T::Type{ACCESSS}, layer::Symbol, date::Dates.TimeType)
    _check_layer(T, layer)
    path = rasterpath(T, layer; date)
    url  = rasterurl(T, layer; date)
    _maybe_download(url, path)
end
