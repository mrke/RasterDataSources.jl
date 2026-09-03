# Shared plumbing for the three ERA5 sources: ERA5 (public GCP ARCO Zarr),
# CDSERA5/CDSERA5Land (CDS job-queue NetCDF), and ECMWFERA5/ECMWFERA5Land
# (CDS-key-gated ECMWF ARCO Zarr).

"""
    CachedCloudSource

Reference to a public, unauthenticated cloud Zarr store with a local cache
directory. Open with `RasterDataSources.open_zarr_store` (needs `using Zarr`).
"""
struct CachedCloudSource
    url::String
    cache::String
end

"""
    CDSZarrSource

Reference to an ECMWF ARCO Zarr store gated by a CDS API key, with a local
cache directory. Open with `RasterDataSources.open_zarr_store` (needs `using Zarr`).

Carries no credential -- the token is resolved lazily inside
`open_zarr_store`, not stored here, so it's never on a struct that could be
printed or logged.
"""
struct CDSZarrSource
    url::String
    cache::String
end

"""
    open_zarr_store(source)

Open a [`CachedCloudSource`](@ref)/[`CDSZarrSource`](@ref) reference,
returning a raw Zarr group. Requires `using Zarr` -- the specific methods
live in the `RasterDataSourcesZarrExt` extension and override this fallback.
"""
open_zarr_store(source) =
    error("Opening a $(typeof(source)) requires Zarr to be loaded. Run `using Zarr` first.")

const CDS_API_URL = "https://cds.climate.copernicus.eu/api"

function _read_cdsapirc()
    url = key = nothing
    rcfile = joinpath(homedir(), ".cdsapirc")
    if isfile(rcfile)
        for line in eachline(rcfile)
            m = match(r"^\s*(url|key)\s*:\s*(.+?)\s*$", line)
            m === nothing && continue
            m[1] == "url" ? (url = something(url, m[2])) : (key = something(key, m[2]))
        end
    end
    (; url, key)
end

"""
    _cds_credentials()

Read CDS API credentials, `ENV["CDSAPI_URL"]`/`ENV["CDSAPI_KEY"]` taking
precedence over a `~/.cdsapirc` file (the format used by the Python
`cdsapi`/`ecmwfr` clients):
```
url: https://cds.climate.copernicus.eu/api
key: <PERSONAL-ACCESS-TOKEN>
```
"""
function _cds_credentials()
    file = _read_cdsapirc()
    url = get(ENV, "CDSAPI_URL", something(file.url, CDS_API_URL))
    key = get(ENV, "CDSAPI_KEY", file.key)
    isnothing(key) && throw(ArgumentError(
        "No CDS API key found. Set `ENV[\"CDSAPI_KEY\"]`, or create `~/.cdsapirc` " *
        "with a `key: <token>` line. Get a personal access token by registering at " *
        "https://cds.climate.copernicus.eu, and accept each dataset's Terms of Use " *
        "on its page there before requesting it (a one-time manual step CDS requires)."
    ))
    (url = rstrip(url, '/'), key = key)
end
