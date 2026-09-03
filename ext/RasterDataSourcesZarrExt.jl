module RasterDataSourcesZarrExt

import Zarr
import HTTP
import RasterDataSources
using RasterDataSources: CDSZarrSource

# Mirrors Zarr.jl's own `HTTPStore` status-code discipline: only 404 means
# "missing key"; anything else (401/403/429/5xx) throws, naming the URL and
# status but never the Authorization header.
# Error bodies/headers from a throttled or failing service usually explain
# themselves (rate limit, quota, retry-after) -- surface that instead of
# just the status code.
function _response_detail(r)
    parts = String[]
    retry_after = HTTP.header(r, "Retry-After", "")
    isempty(retry_after) || push!(parts, "Retry-After: $retry_after")
    body = strip(String(r.body))
    isempty(body) || push!(parts, first(body, 300))
    return join(parts, "; ")
end

struct AuthedHTTPStore <: Zarr.AbstractStore
    url::String
    headers::Vector{Pair{String,String}}
    allowed_codes::Set{Int}
    AuthedHTTPStore(url, headers, allowed_codes = Set((404,))) = new(url, headers, allowed_codes)
end
# 5xx here has been observed as CDS-side rate-limiting after a heavy chunk
# download (confirmed live: an unauthenticated request to the same URL gets
# a clean 401, so the service itself is up) -- capped exponential backoff,
# mirroring `_cds_poll`, gives a cooldown window time to clear. 4xx isn't
# retried since another attempt won't fix an auth/permission problem.
function Base.getindex(s::AuthedHTTPStore, k::AbstractString;
        max_attempts = 5, sleep_seconds = 2.0, max_sleep = 30.0)
    url = string(s.url, "/", k)
    for attempt in 1:max_attempts
        r = HTTP.request("GET", url, s.headers; status_exception = false)
        r.status < 300 && return r.body
        r.status in s.allowed_codes && return nothing
        detail = _response_detail(r)
        if r.status >= 500 && attempt < max_attempts
            @warn "Transient error from CDS ARCO store, retrying" status = r.status url detail
            sleep(sleep_seconds)
            sleep_seconds = min(sleep_seconds * 1.5, max_sleep)
            continue
        end
        error("CDS ARCO store request failed: $(r.status) for $url" *
              (isempty(detail) ? "" : " -- $detail"))
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
