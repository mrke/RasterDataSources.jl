using RasterDataSources, URIs, Extents, Test, Dates
using RasterDataSources: rastername, rasterpath, _cds_area, _cds_request_body, _cds_dataset_id,
    _normalize_cds_variables, _extent_tag

@testset "CDSERA5 / CDSERA5Land" begin

    tas_extent = Extent(X=(143.0, 149.0), Y=(-44.0, -40.0))

    @test _cds_dataset_id(CDSERA5) == "reanalysis-era5-single-levels"
    @test _cds_dataset_id(CDSERA5Land) == "reanalysis-era5-land"

    @test _cds_area(tas_extent) == [-40.0, 143.0, -44.0, 149.0]

    body = _cds_request_body(CDSERA5Land, ("2m_temperature", "total_precipitation"), Date(2020, 2, 1), tas_extent)
    inputs = body["inputs"]
    @test inputs["variable"] == ["2m_temperature", "total_precipitation"]
    @test inputs["year"] == ["2020"]
    @test inputs["month"] == ["02"]
    @test inputs["day"] == [lpad(d, 2, '0') for d in 1:29] # 2020 is a leap year
    @test length(inputs["time"]) == 24
    @test inputs["time"][1] == "00:00"
    @test inputs["time"][end] == "23:00"
    @test inputs["area"] == [-40.0, 143.0, -44.0, 149.0]
    @test inputs["data_format"] == "netcdf"
    @test !haskey(inputs, "product_type")

    body2 = _cds_request_body(CDSERA5, ("2m_temperature",), Date(2021, 1, 1), tas_extent)
    @test body2["inputs"]["product_type"] == "reanalysis"

    @test rasterpath(CDSERA5) == joinpath(ENV["RASTERDATASOURCES_PATH"], "CDS-ERA5")
    @test rasterpath(CDSERA5Land) == joinpath(ENV["RASTERDATASOURCES_PATH"], "CDS-ERA5-Land")

    name1 = rastername(CDSERA5Land, ("2m_temperature",); date=Date(2020, 2, 1), extent=tas_extent)
    name2 = rastername(CDSERA5Land, ("2m_temperature", "total_precipitation"); date=Date(2020, 2, 1), extent=tas_extent)
    @test name1 != name2 # different variable sets must not collide on disk
    @test occursin("202002", name1)
    @test endswith(name1, ".nc")

    @test RasterDataSources.getraster_keywords(CDSERA5Land) == (:date, :extent)
    @test RasterDataSources.date_step(CDSERA5Land) == Month(1)

    @test_throws ArgumentError getraster(CDSERA5Land; date=Date(2020, 2, 1), extent=tas_extent)

    # Same variables, different input order/type/duplicates -> identical
    # normalized tuple -> identical cache path.
    @test _normalize_cds_variables(("tp", "t2m")) == _normalize_cds_variables(("t2m", "tp"))
    name3 = rastername(CDSERA5Land, _normalize_cds_variables(("tp", "t2m")); date=Date(2020, 2, 1), extent=tas_extent)
    name4 = rastername(CDSERA5Land, _normalize_cds_variables(("t2m", "tp")); date=Date(2020, 2, 1), extent=tas_extent)
    @test name3 == name4
    @test _normalize_cds_variables((:t2m, "t2m", "t2m")) == ("t2m",) # Symbol + dupes collapse to one
    @test_throws ArgumentError _normalize_cds_variables(())
    @test_throws ArgumentError _normalize_cds_variables(String[])
    @test_throws ArgumentError _normalize_cds_variables((1, 2))

    # Reversed bounds must error, not silently build a nonsensical area/path.
    @test_throws ArgumentError _extent_tag(Extent(X=(149.0, 143.0), Y=(-44.0, -40.0)))
    @test_throws ArgumentError getraster(CDSERA5Land, "2m_temperature";
        date=Date(2020, 2, 1), extent=Extent(X=(149.0, 143.0), Y=(-44.0, -40.0)))

    # Network access requires a CDS API token -- request/path construction
    # only, no download.
end
