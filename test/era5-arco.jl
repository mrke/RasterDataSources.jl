using RasterDataSources, URIs, Test
using RasterDataSources: rasterpath, layers, getraster_keywords, _ecmwf_arco_group_url, CDSZarrSource,
    open_zarr_store, _check_arco_chunking

@testset "ERA5ECMWF / ERA5ECMWFLand" begin

    @test layers(ERA5ECMWF) == (:sfc, :wav)
    @test :sfc_2m_temperature in layers(ERA5ECMWFLand)
    @test length(layers(ERA5ECMWFLand)) == 8

    @test getraster_keywords(ERA5ECMWF) == (:chunking,)
    @test getraster_keywords(ERA5ECMWFLand) == (:chunking,)

    @test _ecmwf_arco_group_url(ERA5ECMWF, :sfc) ==
        URI(scheme="https", host="arco.datastores.ecmwf.int",
            path="/cadl-arco-geo-002/arco/reanalysis_era5_single_levels/sfc/geoChunked.zarr")
    @test _ecmwf_arco_group_url(ERA5ECMWF, :sfc; chunking=:time) ==
        URI(scheme="https", host="arco.datastores.ecmwf.int",
            path="/cadl-arco-time-002/arco/reanalysis_era5_single_levels/sfc/timeChunked.zarr")
    @test _ecmwf_arco_group_url(ERA5ECMWF, :wav) ==
        URI(scheme="https", host="arco.datastores.ecmwf.int",
            path="/cadl-arco-geo-003/arco/reanalysis_era5_single_levels/wav/geoChunked.zarr")

    @test _ecmwf_arco_group_url(ERA5ECMWFLand, :sfc_2m_temperature) ==
        URI(scheme="https", host="arco.datastores.ecmwf.int",
            path="/cadl-arco-geo-007/arco/reanalysis_era5_land/sfc-2m-temperature/geoChunked.zarr")
    @test _ecmwf_arco_group_url(ERA5ECMWFLand, :sfc_skin_temperature; chunking=:time) ==
        URI(scheme="https", host="arco.datastores.ecmwf.int",
            path="/cadl-arco-time-043/arco/reanalysis_era5_land/sfc-skin-temperature/timeChunked.zarr")

    @test_throws Exception _ecmwf_arco_group_url(ERA5ECMWF, :not_a_group)
    @test_throws ArgumentError _check_arco_chunking(:bogus)

    # Invalid chunking must be rejected before getraster does anything else
    # (in particular, before any cache directory could be created).
    @test_throws ArgumentError getraster(ERA5ECMWF, :sfc; chunking=:bogus)

    # No topic group specified: must error, not silently fetch every group.
    @test_throws ArgumentError getraster(ERA5ECMWF)
    @test_throws ArgumentError getraster(ERA5ECMWF; chunking=:geo)

    era5_path = joinpath(ENV["RASTERDATASOURCES_PATH"], "ECMWF-ARCO-ERA5")
    @test rasterpath(ERA5ECMWF) == era5_path
    land_path = joinpath(ENV["RASTERDATASOURCES_PATH"], "ECMWF-ARCO-ERA5-Land")
    @test rasterpath(ERA5ECMWFLand) == land_path

    # geo- and time-chunked stores for the same group are different remote
    # data and must not share a cache directory (the bug the review caught).
    geo_path = rasterpath(ERA5ECMWFLand, :sfc_2m_temperature; chunking=:geo)
    time_path = rasterpath(ERA5ECMWFLand, :sfc_2m_temperature; chunking=:time)
    @test geo_path != time_path
    @test occursin("geo", geo_path)
    @test occursin("time", time_path)

    rm(geo_path; force=true, recursive=true)
    source = getraster(ERA5ECMWFLand, :sfc_2m_temperature)
    @test source isa CDSZarrSource
    # getraster only builds a reference; no filesystem side effect.
    @test !isdir(source.cache)
    @test source.cache == geo_path
    # No credential/header field -- regression test that a token never
    # gets added back onto this struct.
    @test fieldnames(CDSZarrSource) == (:url, :cache)

    sources = getraster(ERA5ECMWFLand, (:sfc_2m_temperature, :sfc_wind))
    @test sources isa NamedTuple
    @test keys(sources) == (:sfc_2m_temperature, :sfc_wind)
    @test all(s -> s isa CDSZarrSource, sources)

    # Calling this without `using Zarr` loaded must give a clear error
    # (the generic fallback method), not an UndefVarError.
    @test_throws ErrorException open_zarr_store(source)

    # Network access requires a CDS API token and `using Zarr` -- URL/path
    # construction and the pre-extension fallback only, no live open.
end
