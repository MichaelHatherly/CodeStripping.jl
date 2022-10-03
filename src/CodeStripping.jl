module CodeStripping

import Pkg

# Interface.

export strip_code

"""
    strip_code(target)

Remove source code from the provided `target` where `target` can
be any of the following:

  - `String`, project directory
  - `Module` object
  - `Symbol`, name of a package
  - a `Vector` of any of the above

When a `Symbol` representing a package name is provided then the
currently active project is used for lookup, but a second optional
argument can be passed that provides the directory of the project to
perform the lookup in instead.
"""
function strip_code end

function strip_code(pkg::Base.PkgId)
    with_mtime_adjustment(pkg) do path
        name, = splitext(basename(path))
        write(
            path,
            """
            # Code stripped.
            module $name end
            """
        )
    end
end
strip_code(mod::Module) = strip_code(Base.PkgId(mod))

function strip_code(directory::AbstractString)
    if isdir(directory)
        ctx = create_pkg_context(directory)
        package = Symbol(ctx.env.pkg.name)
        return strip_code(package, directory)
    else
        error("`$directory` is not a directory.")
    end
end

function strip_code(package::Symbol, project=dirname(Base.active_project()))
    ctx = create_pkg_context(project)
    package = "$package"
    if ctx.env.pkg.name == package
        pkgid = Base.PkgId(ctx.env.pkg.uuid, ctx.env.pkg.name)
        return strip_code(pkgid)
    else
        deps = ctx.env.project.deps
        return ctx
        if haskey(deps, package)
            pkgid = deps[package]
            return strip_code(pkgid)
        else
            error("`$package` not found in project `$project`.")
        end
    end
end

function strip_code(v::Vector{Symbol}, project=dirname(Base.active_project()))
    for each in v
        strip_code(each, project)
    end
end

strip_code(mod::Module) = strip_code(Base.PkgId(_root_module(mod)))
strip_code(v::Vector) = foreach(strip_code, v)

# Internals.

function _root_module(mod::Module)
    if mod in (Base, Core)
        return mod
    else
        p = parentmodule(mod)
        if p === mod
            return p
        else
            return _root_module(p)
        end
    end
end

function with_mtime_adjustment(func, pkg::Base.PkgId)
    ji_file = Base.compilecache(pkg)
    raw_bytes = read(ji_file)
    _, (includes, _), _, _, _ = Base.parse_cache_header(ji_file)

    for each in includes
        filename = each.filename
        old_mtime = each.mtime

        buffer = IOBuffer()
        write(buffer, filename, old_mtime)
        target_bytes = take!(buffer)

        target_range = findfirst(target_bytes, raw_bytes)

        if isnothing(target_range)
            error("could not find `$filename` in cache header")
        else
            func(filename)
            new_mtime = mtime(filename)

            buffer = IOBuffer()
            write(buffer, filename, new_mtime)
            new_bytes = take!(buffer)

            raw_bytes[target_range] = new_bytes
        end
    end
    raw_bytes_no_crc = raw_bytes[1:end-4]
    write(ji_file, raw_bytes_no_crc, Base._crc32c(raw_bytes_no_crc))
end
with_mtime_adjustment(func, mod::Module) = with_mtime_adjustment(func, Base.PkgId(mod))

# From PackageCompiler.
function create_pkg_context(project)
    project_toml_path = Pkg.Types.projectfile_path(project; strict=true)
    if project_toml_path === nothing
        error("could not find project at $(repr(project))")
    end
    return Pkg.Types.Context(env=Pkg.Types.EnvCache(project_toml_path))
end

end
