using RasterDataSources, URIs, Test
using RasterDataSources: rasterpath, layers, getraster_keywords, _arco_group_url, CDSZarrSource, open_zarr_store

@testset "ECMWFERA5 / ECMWFERA5Land" begin

    @test layers(ECMWFERA5) == (:sfc, :wav)
    @test :sfc_2m_temperature in layers(ECMWFERA5Land)
    @test length(layers(ECMWFERA5Land)) == 8

    @test getraster_keywords(ECMWFERA5) == (:chunking,)
    @test getraster_keywords(ECMWFERA5Land) == (:chunking,)

    @test _arco_group_url(ECMWFERA5, :sfc) ==
        URI(scheme="https", host="arco.datastores.ecmwf.int",
            path="/cadl-arco-geo-002/arco/reanalysis_era5_single_levels/sfc/geoChunked.zarr")
    @test _arco_group_url(ECMWFERA5, :sfc; chunking=:time) ==
        URI(scheme="https", host="arco.datastores.ecmwf.int",
            path="/cadl-arco-time-002/arco/reanalysis_era5_single_levels/sfc/timeChunked.zarr")
    @test _arco_group_url(ECMWFERA5, :wav) ==
        URI(scheme="https", host="arco.datastores.ecmwf.int",
            path="/cadl-arco-geo-003/arco/reanalysis_era5_single_levels/wav/geoChunked.zarr")

    @test _arco_group_url(ECMWFERA5Land, :sfc_2m_temperature) ==
        URI(scheme="https", host="arco.datastores.ecmwf.int",
            path="/cadl-arco-geo-007/arco/reanalysis_era5_land/sfc-2m-temperature/geoChunked.zarr")
    @test _arco_group_url(ECMWFERA5Land, :sfc_skin_temperature; chunking=:time) ==
        URI(scheme="https", host="arco.datastores.ecmwf.int",
            path="/cadl-arco-time-043/arco/reanalysis_era5_land/sfc-skin-temperature/timeChunked.zarr")

    @test_throws ArgumentError _arco_group_url(ECMWFERA5, :sfc; chunking=:bogus)
    @test_throws Exception _arco_group_url(ECMWFERA5, :not_a_group)

    era5_path = joinpath(ENV["RASTERDATASOURCES_PATH"], "ECMWF-ARCO-ERA5")
    @test rasterpath(ECMWFERA5) == era5_path
    land_path = joinpath(ENV["RASTERDATASOURCES_PATH"], "ECMWF-ARCO-ERA5-Land")
    @test rasterpath(ECMWFERA5Land) == land_path

    # geo- and time-chunked stores for the same group are different remote
    # data and must not share a cache directory (the bug the review caught).
    geo_path = rasterpath(ECMWFERA5Land, :sfc_2m_temperature; chunking=:geo)
    time_path = rasterpath(ECMWFERA5Land, :sfc_2m_temperature; chunking=:time)
    @test geo_path != time_path
    @test occursin("geo", geo_path)
    @test occursin("time", time_path)

    source = getraster(ECMWFERA5Land, :sfc_2m_temperature)
    @test source isa CDSZarrSource
    @test isdir(source.cache)
    @test source.cache == geo_path
    # No credential/header field -- regression test that a token never
    # gets added back onto this struct.
    @test fieldnames(CDSZarrSource) == (:url, :cache)

    sources = getraster(ECMWFERA5Land, (:sfc_2m_temperature, :sfc_wind))
    @test sources isa NamedTuple
    @test keys(sources) == (:sfc_2m_temperature, :sfc_wind)
    @test all(s -> s isa CDSZarrSource, sources)

    # Calling this without `using Zarr` loaded must give a clear MethodError
    # (the only method lives in the RasterDataSourcesZarrExt extension),
    # not an UndefVarError.
    @test_throws MethodError open_zarr_store(source)

    # Network access requires a CDS API token and `using Zarr` -- URL/path
    # construction and the pre-extension fallback only, no live open.
end
