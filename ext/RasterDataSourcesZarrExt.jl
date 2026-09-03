module RasterDataSourcesZarrExt

import Zarr
import HTTP
import RasterDataSources
using RasterDataSources: CachedCloudSource, CDSZarrSource

# Response body/Retry-After usually explain a throttled or failing service.
function _response_detail(r)
    parts = String[]
    retry_after = HTTP.header(r, "Retry-After", "")
    isempty(retry_after) || push!(parts, "Retry-After: $retry_after")
    body = strip(String(r.body))
    isempty(body) || push!(parts, first(body, 300))
    return join(parts, "; ")
end

# Mirrors Zarr.jl's own `HTTPStore`, with an `Authorization` header added.
struct AuthedHTTPStore <: Zarr.AbstractStore
    url::String
    headers::Vector{Pair{String,String}}
    allowed_codes::Set{Int}
    AuthedHTTPStore(url, headers, allowed_codes = Set((404,))) = new(url, headers, allowed_codes)
end

function Base.getindex(s::AuthedHTTPStore, k::AbstractString)
    url = string(s.url, "/", k)
    r = HTTP.request("GET", url, s.headers; status_exception = false)
    r.status < 300 && return r.body
    r.status in s.allowed_codes && return nothing
    detail = _response_detail(r)
    error("CDS ARCO store request failed: $(r.status) for $url" *
          (isempty(detail) ? "" : " -- $detail"))
end

_cds_auth_headers() = ["Authorization" => "Bearer $(RasterDataSources._cds_credentials().key)"]

# `zopen` only auto-wraps in `ConsolidatedStore` for its string-based
# constructor; an already-built store (as here) needs it wrapped explicitly,
# or it silently returns a group with zero arrays.
_open_zarr_store(store, cache) =
    Zarr.zopen(Zarr.ConsolidatedStore(Zarr.CachingStore(store, Zarr.DirectoryStore(cache)), ""))

RasterDataSources.open_zarr_store(source::CachedCloudSource) =
    _open_zarr_store(Zarr.HTTPStore(source.url), source.cache)
RasterDataSources.open_zarr_store(source::CDSZarrSource) =
    _open_zarr_store(AuthedHTTPStore(source.url, _cds_auth_headers()), source.cache)

end
