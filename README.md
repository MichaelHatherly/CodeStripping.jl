# CodeStripping.jl

Remove source code from `.jl` without causing `.ji` files to become stale.

## Installation

```
julia> import Pkg; Pkg.add(url = "https://github.com/MichaelHatherly/CodeStripping.jl")
```

## Usage

```
import CodeStripping
import LoadedPackage
CodeStripping.strip_code(LoadedPackage)
CodeStripping.strip_code(:PackageInCurrentEnvironment)
CodeStripping.strip_code("this/julia/file.jl")
CodeStripping.strip_code("../this/julia/environment/")
CodeStripping.strip_code([Several, :Loaded, "file.jl"])
CodeStripping.strip_code([:Packages, :From, :Another, :Project], "project/env")
```

> ***Warning:***
>
> `strip_code` is not a recoverable function. If you run it on code that you do not
> have a backup of then that code will be lost. Use with caution!

