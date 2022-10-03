using CodeStripping
using Test

@testset "CodeStripping" begin
    mktempdir() do tmp
        pushfirst!(LOAD_PATH, joinpath(tmp, "Project.toml"))
        try
            name = "TestPackage"
            uuid = "a2de5692-967f-a7db-685c-be5db730c223"
            write(joinpath(tmp, "Project.toml"),
                """
                name = "$name"
                uuid = "$uuid"
                version = "0.1.0"
                """)

            write(joinpath(tmp, "Manifest.toml"),
                """
                julia_version = "$VERSION"
                manifest_format = "2.0"
                """)

            mkdir(joinpath(tmp, "src"))

            source_file = joinpath(tmp, "src", "$name.jl")
            write(source_file,
                """
                module $name

                # Contents goes here.

                end
                """)

            pkg_id = Base.PkgId(Base.UUID(uuid), name)

            ji_file = Base.compilecache(pkg_id)

            @test contains(read(source_file, String), "# Contents goes here.")
            @test !contains(read(source_file, String), "# Code stripped.")
            @test !contains(read(source_file, String), "module $name end")

            @test Base.stale_cachefile(source_file, ji_file) isa Vector

            sleep(1)

            CodeStripping.strip_code(pkg_id)

            sleep(1)

            @test Base.stale_cachefile(source_file, ji_file) isa Vector

            @test !contains(read(source_file, String), "# Contents goes here.")
            @test contains(read(source_file, String), "# Code stripped.")
            @test contains(read(source_file, String), "module $name end")

            # Wait a bit before writing a change that should be registered.
            sleep(1)

            write(source_file,
                """
                module $name

                # New contents goes here.

                end
                """)

            @test Base.stale_cachefile(source_file, ji_file)
        finally
            popfirst!(LOAD_PATH)
        end
    end
end

