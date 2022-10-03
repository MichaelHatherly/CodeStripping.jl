using CodeStripping
using Logging
using Pkg
using Test

function check_for_stale_cache_files(mod::Module)
    pkg_id = Base.PkgId(mod)
    pkg_root = joinpath(pkgdir(mod), "src", "CodeStripping.jl")
    results = Bool[]
    for each in Base.find_all_in_cache_path(pkg_id)
        result = Base.stale_cachefile(pkg_root, each)
        isa(result, Vector) && push!(results, mod in result)
    end
    return isempty(results) ? false : all((==)(false), results)
end

@testset "CodeStripping" begin
    @testset "Internals" begin
        t = mtime(@__FILE__)
        CodeStripping._preserve_mtime(@__FILE__) do path
            touch(path)
        end
        @test t ≈ mtime(@__FILE__) # Last digit seems to change when using `futime`.

        # Check whether there is a usable ji file, then touch
        # a file that should cause a cache invalidation and recheck,
        # once with our preserve_mtimes wrapper and then once without.
        test_file = joinpath(@__DIR__, "..", "src", "test.jl")

        @test check_for_stale_cache_files(CodeStripping)

        CodeStripping._preserve_mtime(test_file) do path
            touch(path)
        end
        @test check_for_stale_cache_files(CodeStripping)

        touch(test_file)
        @test !check_for_stale_cache_files(CodeStripping)
    end
    @testset "Code stripping" begin
        mktempdir() do dir
            pkg_name = "TempPackage"
            cd(dir) do
                Pkg.generate(pkg_name; io=IOBuffer())
            end
            pkg_path = joinpath(dir, pkg_name)
            @test isdir(pkg_path)

            # First ensure that the package is usable, it has a function called `greet`.
            cmd = `$(Base.julia_cmd()) --project=$(pkg_path) -e 'using TempPackage; TempPackage.greet()'`
            @test success(cmd)

            # Then strip out the source code.
            @test_logs(
                (:debug, "stripped source code"),
                min_level = Logging.Debug,
                CodeStripping.strip_code(:TempPackage, pkg_path)
            )

            source_file = joinpath(pkg_path, "src", "$pkg_name.jl")

            @test !contains(read(source_file, String), "greet()")
            @test contains(read(source_file, String), CodeStripping.STRIPPED_SOURCE_COMMENT)
            @test contains(read(source_file, String), "module $pkg_name end")

            # Check whether we can still call the greet function, since the cache file should
            # not be classed as stale and we should be able to load `greet` directly from it.
            @test success(cmd)

            # Next, we adjust the mtime of the source file so cause a recompilation and check
            # whether we can now not call the greet function, since it shouldn't exist any more.
            touch(source_file)
            @test !success(cmd)
        end
    end
end

