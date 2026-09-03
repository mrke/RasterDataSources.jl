module RasterDataSourcesZarrExt

import Zarr
import HTTP
import RasterDataSources
using RasterDataSources: CDSZarrSource

# Mirrors Zarr.jl's own `HTTPStore` status-code discipline: only 404 means
# "missing key"; anything else (401/403/429/5xx) throws, naming the URL and
# status but never the Authorization header.
struct AuthedHTTPStore <: Zarr.AbstractStore
    url::String
    headers::Vector{Pair{String,String}}
    allowed_codes::Set{Int}
    AuthedHTTPStore(url, headers, allowed_codes = Set((404,))) = new(url, headers, allowed_codes)
end
# Retries 5xx (the ARCO beta service occasionally 503s) with the same
# backoff as `_cds_submit`; 4xx isn't retried since another attempt won't
# fix an auth/permission problem.
function Base.getindex(s::AuthedHTTPStore, k::AbstractString; max_attempts = 3)
    url = string(s.url, "/", k)
    for attempt in 1:max_attempts
        r = HTTP.request("GET", url, s.headers; status_exception = false)
        r.status < 300 && return r.body
        r.status in s.allowed_codes && return nothing
        if r.status >= 500 && attempt < max_attempts
            @warn "Transient error from CDS ARCO store, retrying" status = r.status url
            sleep(2.0 * attempt)
            continue
        end
        error("CDS ARCO store request failed: $(r.status) for $url")
    end
end

_cds_auth_headers() = ["Authorization" => "Bearer $(RasterDataSources._cds_credentials().key)"]

# `CachingStore`'s docstring says `zopen` auto-wraps it in `ConsolidatedStore`
# -- true only for its string-based convenience constructor. Passing an
# already-built store (as here) skips that, silently returning a group with
# zero arrays (confirmed live) unless wrapped explicitly.
RasterDataSources.open_zarr_store(source::CDSZarrSource) = Zarr.zopen(
    Zarr.ConsolidatedStore(
        Zarr.CachingStore(
            AuthedHTTPStore(source.url, _cds_auth_headers()),
            Zarr.DirectoryStore(source.cache),
        ),
        "",
    )
)

end
