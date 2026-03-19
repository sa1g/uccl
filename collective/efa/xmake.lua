-- EFA collective plugin - EFA transport + custom NCCL
-- Produces: libnccl-net-efa.so + libnccl-efa.so (custom NCCL)

local backend = get_config("backend")
local arch = get_config("arch")

-- Skip on ARM or non-CUDA
if arch == "aarch64" or backend:find("rocm") or backend == "therock" then
    function on_load()
        -- Skip this target
        set_kind("phony")
        print("[efa] Skipping EFA build on " .. arch .. " or non-CUDA backend")
    end
    return
end

-- Main EFA plugin
target("ccl_efa")
    set_kind("shared")
    set_basename("libnccl-net-efa")
    set_targetdir("$(buildir)/lib")
    
    local src_files = os.files("*.cc")
    src_files = table.filter(src_files, function(f) 
        return not f:match("_test%.cc$")
    end)
    add_files(table.unpack(src_files))
    
    add_includedirs(".", "$(projectdir)/include")
    
    local cuda_home = (os.getenv("CUDA_HOME") or "/usr/local/cuda")
    local efa_home = (os.getenv("EFA_HOME") or "/opt/amazon/efa")
    
    add_includedirs(cuda_home .. "/include", efa_home .. "/include")
    add_linkdirs(cuda_home .. "/lib64", efa_home .. "/lib")
    add_links("efa", "cudart", "z", "elf", "pthread")
    
    add_cxxflags("-O3", "-std=c++17", "-fPIC", "-Wno-pointer-arith")
    add_defines("USE_CUDA")
    
    if get_config("use_intel_rdma_nic") then
        add_defines("INTEL_RDMA_NIC")
    end
    
    on_install(function(target)
        os.mkdir("$(projectdir)/uccl/lib")
        os.cp(target:targetfile(), "$(projectdir)/uccl/lib/")
    end)
target_end()

-- Custom NCCL for EFA (dependency for P2P)
target("nccl_efa")
    set_kind("shared")
    set_basename("libnccl-efa")
    set_targetdir("$(buildir)/lib")
    
    -- Build from thirdparty/nccl-sg
    set_sourcedir("$(projectdir)/thirdparty/nccl-sg")
    
    on_build(function(target)
        -- Invoke nccl-sg Makefile
        local cuda_home = (os.getenv("CUDA_HOME") or "/usr/local/cuda")
        os.execv("make", {
            "-C", "$(projectdir)/thirdparty/nccl-sg",
            "src.build",
            "-j" .. os.cpu_count(),
            "CUDA_HOME=" .. cuda_home,
            "NVCC_GENCODE=-gencode=arch=compute_90,code=sm_90",
            "USE_INTEL_RDMA_NIC=" .. (get_config("use_intel_rdma_nic") and "1" or "0")
        })
    end)
    
    on_install(function(target)
        os.mkdir("$(projectdir)/uccl/lib")
        os.cp("$(projectdir)/thirdparty/nccl-sg/build/lib/libnccl.so", 
              "$(projectdir)/uccl/lib/libnccl-efa.so")
    end)
target_end()