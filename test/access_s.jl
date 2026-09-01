using RasterDataSources, URIs, Test, Dates
using RasterDataSources: rastername, rasterurl, rasterpath

@testset "ACCESSS" begin

    access_s_path = joinpath(ENV["RASTERDATASOURCES_PATH"], "ACCESS-S2")
    @test rasterpath(ACCESSS) == access_s_path

    @test rastername(ACCESSS, :rain; date=Date(2026, 7, 1)) == "20260701_rain.nc"
    @test rastername(ACCESSS, :tmax; date=Date(2026, 7, 1)) == "20260701_tmax.nc"

    @test rasterpath(ACCESSS, :rain; date=Date(2026, 7, 1)) ==
        joinpath(access_s_path, "rain", "20260701_rain.nc")

    @test rasterurl(ACCESSS, :rain; date=Date(2026, 7, 1)) ==
        URI(scheme="https", host="senaps.net",
            path="/thredds/fileServer/org_catalogs/csiro-dews/DEWS/access_s_downscaled_silo/20260701/20260701_rain.nc")

    @test RasterDataSources.getraster_keywords(ACCESSS) == (:date,)
    @test RasterDataSources.layers(ACCESSS) == (:rain, :tmax, :tmin, :radn, :evap, :vapr)
    @test RasterDataSources.date_step(ACCESSS) == Month(1)

    # Network access is unverified (auth requirement unconfirmed) and files
    # are several GB each -- path/name/url construction only, no download.
end
