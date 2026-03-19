-- Microkernel utilities

local backend = get_config("backend")
local arch = get_config("arch")

-- Skip on non-CUDA or ARM
if arch == "aarch64" or backend:find("rocm") or backend == "therock" then
    return
end

target("ukernel")
    set_kind("shared")
    set_targetdir("$(buildir)/lib")
    
    add_files("*.cu")
    
    local cuda_home = (os.getenv("CUDA_HOME") or "/usr/local/cuda")
    add_includedirs(cuda_home .. "/include", "$(projectdir)/include")
    add_linkdirs(cuda_home .. "/lib64")
    add_links("cudart")
    
    local sm = os.iorun("nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n1 | tr -d '.' | sed 's/\\.//'"):trim() or "90"
    add_nvccflags("-gencode=arch=compute_" .. sm .. ",code=sm_" .. sm)
    
    on_install(function(target)
        os.mkdir("$(projectdir)/uccl/lib")
        os.cp(target:targetfile(), "$(projectdir)/uccl/lib/")
    end)
target_end()