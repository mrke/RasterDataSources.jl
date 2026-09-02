
# Shared client for the Copernicus Climate Data Store (CDS) "new" REST API
# (an OGC API - Processes service), used by both CDSERA5 and CDSERA5Land
# below. Unlike every other source in this package, a CDS request is an
# asynchronous job: submit -> poll until done -> download a result URL.
# There is no static per-file URL to hand to `_maybe_download`.

@doc """
    CDSERA5 <: RasterDataSource

Data from ERA5 (the reanalysis behind the [`ERA5`](@ref) Zarr source in this
package), accessed instead via the Copernicus Climate Data Store (CDS) API --
the same route used by the R package
[mcera5](https://github.com/dklinges9/mcera5) to drive NicheMapR microclimate
runs. Unlike [`ERA5`](@ref), this downloads a regional NetCDF subset (one
month at a time, all requested variables in one file) rather than lazily
streaming from a global Zarr store, which is the right tool for extracting a
multi-year hourly time series over a small area (e.g. a state or a point
buffer) rather than browsing the whole 1940-present global archive.

Resolution ~31 km (0.25°). Maps specifically to the CDS `reanalysis-era5-single-levels`
dataset -- despite the name, this does **not** cover ERA5 pressure-level
variables (e.g. `hus850`, `ta500`), which aren't implemented here. See
[`CDSERA5Land`](@ref) for the ~9 km land-only dataset.

CDS requests are queued server-side; `getraster` submits a job and blocks on
`_cds_poll` until it completes, from seconds to tens of minutes depending on
area/variable count. Results are cached to disk keyed by dataset, month,
bounding box, and the exact variable set requested, so a repeated call is
instant after the first download.

`extent` is interpreted as geographic WGS84 longitude/latitude, matching
this package's `Extents.Extent` convention elsewhere (e.g. [`SRTM`](@ref));
extents that cross the antimeridian (e.g. `X=(170, -170)`) are not
supported.

# Setup (one-time, outside Julia)
1. Register at [cds.climate.copernicus.eu](https://cds.climate.copernicus.eu)
   and copy your personal access token.
2. Accept the Terms of Use for the
   [ERA5 hourly single levels](https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels)
   dataset on its page (required once, before any API request succeeds).
3. Save the token to `~/.cdsapirc` (see `RasterDataSources._cds_credentials`),
   or set `ENV["CDSAPI_KEY"]`.

# Usage with `getraster`
    getraster(T::Type{CDSERA5}, variables; date, extent)

# Arguments
- `variables`: a CDS variable name `String` (e.g. `"2m_temperature"`), or a
    `Tuple`/`Vector` of them, all downloaded together into one NetCDF file.
    Deliberately a `String`, not the `Symbol` this package otherwise uses for
    `layer`: the ERA5 single-levels catalog has 100+ variables, many of them
    (e.g. `"2m_temperature"`) not valid `Symbol` literals, and isn't
    meaningfully enumerable as this package's usual `layers` trait. See the
    [CDS ERA5 single-levels variable list](https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels)
    for valid names.

# Keywords
- `date`: a `Date`, or a `Tuple` of start/end dates. Only the year and month
    are used -- each covers its whole calendar month. A date range returns a
    `Vector` of monthly paths.
- `extent`: an `Extents.Extent` bounding box, e.g.
    `Extent(X=(143.0, 149.0), Y=(-44.0, -40.0))` for Tasmania.

# Example
```julia
using RasterDataSources, Extents, Dates
getraster(CDSERA5, ("2m_temperature", "total_precipitation");
    date=(Date(2020,1,1), Date(2020,12,31)), extent=Extent(X=(143.0,149.0), Y=(-44.0,-40.0)))
```

!!! warning
    Two details of the request/response shape are unverified against a live
    CDS response: the exact JSON key path to the download link in a job's
    `/results`, and whether `area` is accepted as a 4-element numeric array
    in the current API (vs. the legacy `"N/W/S/E"` string). Both are
    isolated in `RasterDataSources._cds_result_href` and
    `RasterDataSources._cds_area` respectively, for a one-line fix if a real
    request disagrees.
""" CDSERA5
struct CDSERA5 <: RasterDataSource end

@doc """
    CDSERA5Land <: RasterDataSource

Data from ERA5-Land, the land-only, higher-resolution (~9 km / 0.1°)
companion to ERA5, accessed via the Copernicus Climate Data Store (CDS) API.
See [`CDSERA5`](@ref) for the full description, setup steps, and usage --
everything there applies here except the dataset id and resolution. Accept
the Terms of Use for the
[ERA5-Land hourly](https://cds.climate.copernicus.eu/datasets/reanalysis-era5-land)
dataset specifically (separate from the ERA5 single-levels one).

# Example
```julia
using RasterDataSources, Extents, Dates
getraster(CDSERA5Land, "2m_temperature";
    date=Date(2020,7,1), extent=Extent(X=(143.0,149.0), Y=(-44.0,-40.0)))
```
""" CDSERA5Land
struct CDSERA5Land <: RasterDataSource end

const CDS_API_URL = "https://cds.climate.copernicus.eu/api"

"""
    _cds_credentials()

Read CDS API credentials from `ENV["CDSAPI_URL"]`/`ENV["CDSAPI_KEY"]`, falling
back to a `~/.cdsapirc` file (the format used by the Python `cdsapi`/`ecmwfr`
clients, so an existing mcera5/cdsapi setup needs no extra configuration):
```
url: https://cds.climate.copernicus.eu/api
key: <PERSONAL-ACCESS-TOKEN>
```
"""
function _cds_credentials()
    url = get(ENV, "CDSAPI_URL", nothing)
    key = get(ENV, "CDSAPI_KEY", nothing)
    if isnothing(key)
        rcfile = joinpath(homedir(), ".cdsapirc")
        if isfile(rcfile)
            for line in eachline(rcfile)
                m = match(r"^\s*(url|key)\s*:\s*(.+?)\s*$", line)
                m === nothing && continue
                if m[1] == "url"
                    url = something(url, m[2])
                elseif m[1] == "key"
                    key = something(key, m[2])
                end
            end
        end
    end
    isnothing(key) && throw(ArgumentError(
        "No CDS API key found. Set `ENV[\"CDSAPI_KEY\"]`, or create `~/.cdsapirc` " *
        "with a `key: <token>` line. Get a personal access token by registering at " *
        "https://cds.climate.copernicus.eu, and accept each dataset's Terms of Use " *
        "on its page there before requesting it (a one-time manual step CDS requires)."
    ))
    (url = something(url, CDS_API_URL), key = key)
end

_cds_dataset_id(::Type{CDSERA5}) = "reanalysis-era5-single-levels"
_cds_dataset_id(::Type{CDSERA5Land}) = "reanalysis-era5-land"

# mcera5's CDS requests set this for ERA5 single-levels; ERA5-Land has only
# one product internally and doesn't take the field. Unverified whether the
# current API rejects it outright vs. just ignoring it for ERA5-Land.
_cds_extra_inputs(::Type{CDSERA5}) = Dict{String,Any}("product_type" => "reanalysis")
_cds_extra_inputs(::Type{CDSERA5Land}) = Dict{String,Any}()

# N/W/S/E, matching mcera5's `build_era5_request.R` area convention.
function _cds_area(extent::Extents.Extent)
    xmin, xmax = extent.X
    ymin, ymax = extent.Y
    [ymax, xmin, ymin, xmax]
end

# Pure/testable: builds the `{"inputs": {...}}` body for one calendar month,
# requesting every hour of every day, for all `variables` in one job. CDS
# variable names are plain strings (e.g. "2m_temperature") rather than
# `Symbol`s -- see the CDSERA5/CDSERA5Land docstrings for why.
function _cds_request_body(
    T::Type{<:Union{CDSERA5,CDSERA5Land}}, variables::Tuple{Vararg{AbstractString}},
    date::Dates.TimeType, extent::Extents.Extent,
)
    days = [lpad(d, 2, '0') for d in 1:daysinmonth(date)]
    times = [lpad(h, 2, '0') * ":00" for h in 0:23]
    inputs = Dict{String,Any}(
        "variable" => collect(String, variables),
        "year" => [Dates.format(date, "yyyy")],
        "month" => [Dates.format(date, "mm")],
        "day" => days,
        "time" => times,
        "area" => _cds_area(extent),
        "data_format" => "netcdf",
        "download_format" => "unarchived",
    )
    merge!(inputs, _cds_extra_inputs(T))
    Dict("inputs" => inputs)
end

function _cds_submit(T::Type{<:Union{CDSERA5,CDSERA5Land}}, body::Dict)
    creds = _cds_credentials()
    r = HTTP.request("POST", "$(creds.url)/processes/$(_cds_dataset_id(T))/execution",
        ["PRIVATE-TOKEN" => creds.key, "Content-Type" => "application/json"], JSON.json(body))
    JSON.parse(String(r.body))["jobID"]
end

# Capped exponential backoff, mirroring `_maybe_download`'s retry style.
# Bounded by `max_attempts` so a stalled job can't hang forever; also
# retries a few transient HTTP errors while polling.
function _cds_poll(job_id::AbstractString; sleep_seconds = 2.0, max_sleep = 60.0, max_attempts = 200)
    creds = _cds_credentials()
    url = "$(creds.url)/jobs/$job_id"
    for attempt in 1:max_attempts
        status = try
            r = HTTP.request("GET", url, ["PRIVATE-TOKEN" => creds.key])
            JSON.parse(String(r.body))["status"]
        catch e
            attempt == max_attempts && rethrow(e)
            @warn "Transient error polling CDS job $job_id, retrying" exception = e
            sleep(sleep_seconds)
            sleep_seconds = min(sleep_seconds * 1.5, max_sleep)
            continue
        end
        status == "successful" && return nothing
        status in ("failed", "dismissed", "rejected") &&
            error("CDS job $job_id ended with status \"$status\"")
        sleep(sleep_seconds)
        sleep_seconds = min(sleep_seconds * 1.5, max_sleep)
    end
    error("CDS job $job_id did not complete after $max_attempts polling attempts")
end

# Exact key path to the download link is unverified against a live
# response -- isolated here for a one-line fix if the real shape differs.
_cds_result_href(body::Dict) =
    (asset = body["asset"]; asset isa Dict && haskey(asset, "value") ? asset["value"]["href"] : asset["href"])

# NetCDF classic starts with magic bytes "CDF"; NetCDF4 is HDF5-based,
# starting with "\x89HDF". Whether CDS returns one file or a ZIP for a
# multi-variable request is unverified (see the CDSERA5 docstring warning) --
# check before caching the download at a `.nc` path.
function _check_netcdf(path)
    magic = open(io -> read(io, 8), path)
    is_netcdf = length(magic) >= 4 && (
        magic[1:3] == UInt8[0x43, 0x44, 0x46] ||               # "CDF"
        magic[1:4] == UInt8[0x89, 0x48, 0x44, 0x46]             # "\x89HDF"
    )
    is_netcdf || error(
        "Downloaded file at $path does not look like NetCDF (magic bytes $(magic)). " *
        "CDS may have returned a ZIP archive or an error document instead of a single NetCDF file."
    )
end

function _cds_download_result(job_id::AbstractString, target_path)
    creds = _cds_credentials()
    r = HTTP.request("GET", "$(creds.url)/jobs/$job_id/results", ["PRIVATE-TOKEN" => creds.key])
    href = _cds_result_href(JSON.parse(String(r.body)))
    mkpath(dirname(target_path))
    try
        HTTP.download(href, target_path)
        _check_netcdf(target_path)
    catch e
        # Don't leave an invalid/partial file behind for a later call to
        # mistake for a completed download, same convention as `_maybe_download`.
        isfile(target_path) && rm(target_path)
        rethrow(e)
    end
    target_path
end

_check_extent_order(extent::Extents.Extent) =
    (extent.X[1] > extent.X[2] || extent.Y[1] > extent.Y[2]) &&
        throw(ArgumentError("`extent` has an upper bound below its lower bound: $extent"))

# Directory name from a bounding box, filesystem-safe. Rounded to 4 decimal
# places (~11 m) so distinct bboxes don't collide onto the same tag.
function _extent_tag(extent::Extents.Extent)
    _check_extent_order(extent)
    xmin, xmax = extent.X
    ymin, ymax = extent.Y
    tag = join(round.((xmin, xmax, ymin, ymax); digits = 4), "_")
    replace(tag, "-" => "m", "." => "p")
end

# Distinct requests for the same month/extent but different `variables` must
# not collide on disk (or a later request with more variables would find the
# earlier, incomplete file already there and silently skip downloading).
# Callers always pass an already-`_normalize_cds_variables`-sorted tuple, so
# equal variable sets in a different input order share a cache entry.
_variables_tag(variables::Tuple{Vararg{AbstractString}}) = string(hash(variables); base = 16)

# Accepts a single `String`/`Symbol`, or a collection of them. Rejects an
# empty request, de-duplicates, sorts (so input order doesn't affect the
# cache path or the request sent to CDS), and errors on any other element
# type instead of silently stringifying e.g. an `Int`.
function _normalize_cds_variables(variables)
    items = variables isa Union{AbstractString,Symbol} ? (variables,) : collect(variables)
    isempty(items) && throw(ArgumentError("at least one CDS variable must be specified"))
    result = String[]
    for v in items
        v isa Union{AbstractString,Symbol} || throw(ArgumentError(
            "CDS variable names must be `String` or `Symbol`, got a `$(typeof(v))`: $v"
        ))
        s = string(v)
        s in result || push!(result, s)
    end
    Tuple(sort(result))
end

date_step(::Type{<:Union{CDSERA5,CDSERA5Land}}) = Month(1)
date_range(::Type{CDSERA5}) = (Date(1940, 1, 1), Date(year(today()), 12, 31))
date_range(::Type{CDSERA5Land}) = (Date(1950, 1, 1), Date(year(today()), 12, 31))
getraster_keywords(::Type{<:Union{CDSERA5,CDSERA5Land}}) = (:date, :extent)

# Deliberately not reusing the plain "ERA5" folder: the existing `ERA5` type
# already caches its Zarr store at `rasterpath()/ERA5/arco-era5-zarr`
# (era5.jl), and this is an unrelated cache of monthly regional NetCDFs.
rasterpath(::Type{CDSERA5}) = joinpath(rasterpath(), "CDS-ERA5")
rasterpath(::Type{CDSERA5Land}) = joinpath(rasterpath(), "CDS-ERA5-Land")

rastername(::Type{<:Union{CDSERA5,CDSERA5Land}}, variables::Tuple{Vararg{AbstractString}}; date, extent) =
    "$(Dates.format(date, "yyyymm"))_$(length(variables))vars-$(_variables_tag(variables)).nc"

function rasterpath(
    T::Type{<:Union{CDSERA5,CDSERA5Land}}, variables::Tuple{Vararg{AbstractString}}; date, extent::Extents.Extent,
)
    joinpath(rasterpath(T), _extent_tag(extent), rastername(T, variables; date, extent))
end

# Overrides shared.jl's generic `getraster(T; kw...) = getraster(T, layers(T); kw...)`
# fallback with a clear error, since `layers(T)` is deliberately undefined
# for this open-ended-catalog source (see docstrings above).
getraster(T::Type{<:Union{CDSERA5,CDSERA5Land}}; kw...) = throw(ArgumentError(
    "variables must be specified, e.g. getraster($T, \"2m_temperature\"; date, extent)"
))
getraster(T::Type{<:Union{CDSERA5,CDSERA5Land}}, variable::Union{AbstractString,Symbol}; date, extent) =
    _getraster(T, _normalize_cds_variables(variable), date, extent)
getraster(T::Type{<:Union{CDSERA5,CDSERA5Land}}, variables::Tuple; date, extent) =
    _getraster(T, _normalize_cds_variables(variables), date, extent)

function _getraster(T::Type{<:Union{CDSERA5,CDSERA5Land}}, variables::Tuple, dates::Tuple{<:Any,<:Any}, extent)
    _getraster(T, variables, date_sequence(T, dates), extent)
end
function _getraster(T::Type{<:Union{CDSERA5,CDSERA5Land}}, variables::Tuple, dates::AbstractArray, extent)
    _getraster.(T, Ref(variables), dates, Ref(extent))
end
function _getraster(
    T::Type{<:Union{CDSERA5,CDSERA5Land}}, variables::Tuple{Vararg{AbstractString}},
    date::Dates.TimeType, extent::Extents.Extent,
)
    path = rasterpath(T, variables; date, extent)
    if !isfile(path)
        job_id = _cds_submit(T, _cds_request_body(T, variables, date, extent))
        @info "Submitted CDS job $job_id for $(_cds_dataset_id(T)) $(Dates.format(date, "yyyy-mm"))"
        _cds_poll(job_id)
        _cds_download_result(job_id, path)
    end
    path
end
