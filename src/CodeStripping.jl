module CodeStripping

import Base.Filesystem
import Pkg

# Interface.

export strip_code

"""
    strip_code(target)

Remove source code from the provided `target` where `target` can
be any of the following:

  - `String`, directory or source file
  - `Module` object
  - `Symbol`, name of a package
  - a `Vector` of any of the above

When a `Symbol` representing a package name is provided then the
currently active project is used for lookup, but a second optional
argument can be passed that provides the directory of the project to
perform the lookup in instead.
"""
function strip_code end

function strip_code(path::AbstractString)
    if isdir(path)
        for each in ("JuliaProject.toml", "Project.toml")
            toml = joinpath(path, each)
            if isfile(toml)
                strip_code(toml)
            end
        end
        error("`$path` is not a valid project directory.")
    else
        if isfile(path)
            _, ext = splitext(path)
            if ext == ".jl"
                _preserve_mtime(_strip_code, path)
            elseif ext == ".toml"
                ctx = create_pkg_context(dirname(path))
                package = Symbol(ctx.env.pkg.name)
                return strip_code(package, dirname(path))
            else
                error("unsupported file type `$path`, only .jl and .toml files are supported.")
            end
        else
            error("unsupported path `$path`, only files and directories are supported.")
        end
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
strip_code(pkgid::Base.PkgId) = strip_code(_included_files(pkgid))
strip_code(v::Vector) = foreach(strip_code, v)

# Internals.

const STRIPPED_SOURCE_COMMENT = "# Source code for this file has been stripped."
function _strip_code(file::AbstractString)
    open(file, "w") do io
        println(io, STRIPPED_SOURCE_COMMENT)
        # Always add a "stub" module to the file matching it's file name
        # so that the root file of a package is loadable by `julia`, but
        # just results in an empty module object.
        name, = splitext(basename(file))
        println(io, "module $name end")
    end
    @debug "stripped source code" file
end

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

function _included_files(pkgid::Base.PkgId)
    cachefile = _most_recent_cache_file(pkgid)
    open(cachefile, "r") do io
        if !Base.isvalid_cache_header(io)
            error("Rejecting cache file $cachefile due to it containing an invalid cache header.")
        end
        _, (includes, _), _, _, _, _ = Base.parse_cache_header(io)
        return [each.filename for each in includes]
    end
end

function _most_recent_cache_file(pkgid::Base.PkgId)
    ji_files = Base.find_all_in_cache_path(pkgid)
    if isempty(ji_files)
        error("could not find any ji files for `$pkgid`.")
    else
        sort!(ji_files; by=mtime, rev=true)
        return first(ji_files)
    end
end

function _preserve_mtime(func::Function, path::AbstractString)
    original_mtime = Base.mtime(path)
    result = func(path)
    file_handle = Filesystem.open(path, Filesystem.JL_O_WRONLY | Filesystem.JL_O_CREAT, 0o0666)
    try
        Filesystem.futime(file_handle, original_mtime, original_mtime)
    finally
        Filesystem.close(file_handle)
    end
    return result
end

# From PackageCompiler.
function create_pkg_context(project)
    project_toml_path = Pkg.Types.projectfile_path(project; strict=true)
    if project_toml_path === nothing
        error("could not find project at $(repr(project))")
    end
    return Pkg.Types.Context(env=Pkg.Types.EnvCache(project_toml_path))
end

include("test.jl")

end
