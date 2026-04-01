-- RDMA collective plugin - NCCL network plugin
-- Produces: libnccl-net-uccl.so or librccl-net-uccl.so

local backend = get_config("backend")
local use_intel_rdma_nic = get_config("use_intel_rdma_nic")

-- Determine backend-specific output name
local output_name = (backend:find("rocm") or backend == "therock") and "librccl-net-uccl" or "libnccl-net-uccl"

target("ccl_rdma")
    set_kind("shared")
    set_basename(output_name)
    set_targetdir("$(builddir)/lib")
    
    -- Source files: exclude tests and plugins for library build
    local src_files = os.files("*.cc")
    src_files = table.filter(src_files, function(f) 
        return not f:match("_test%.cc$") and not f:match("_plugin%.cc$")
    end)
    add_files(table.unpack(src_files))
    
    -- Include paths
    add_includedirs(".", 
        "$(projectdir)/include",
        "$(projectdir)/thirdparty/nccl/build/include",
        "$(projectdir)/thirdparty/nccl/src/include")
    
    -- CUDA paths
    local cuda_home = (os.getenv("CUDA_HOME") or "/usr/local/cuda")
    add_includedirs(cuda_home .. "/include")
    add_linkdirs(cuda_home .. "/lib64")
    
    -- Dependencies
    add_links("ibverbs", "cudart", "z", "elf", "pthread")
    
    -- Compiler flags
    add_cxxflags("-O3", "-std=c++17", "-fPIC", "-Wno-pointer-arith", "-Wno-interference-size")
    
    -- Feature flags
    if get_config("use_intel_rdma_nic") then
        add_defines("INTEL_RDMA_NIC")
    end
    
    -- Backend-specific flags
    if backend:find("rocm") or backend == "therock" then
        add_defines("USE_ROCM")
        local rocm_home = os.getenv("ROCM_PATH") or "/opt/rocm"
        add_includedirs(rocm_home .. "/include")
        add_linkdirs(rocm_home .. "/lib")
    else
        add_defines("USE_CUDA")
    end
    
    -- Install to uccl/lib/
    on_install(function(target)
        os.mkdir("$(projectdir)/uccl/lib")
        os.cp(target:targetfile(), "$(projectdir)/uccl/lib/")
    end)
target_end()

-- Tests (optional, not built by default)
if get_config("build_tests") then
    for _, test_file in ipairs(os.files("*_test.cc")) do
        local test_name = test_file:match("([^/]+)_test%.cc$")
        target("ccl_rdma_" .. test_name)
            set_kind("binary")
            set_targetdir("$(builddir)/tests")
            add_files(test_file)
            
            -- Reuse library portions
            local lib_files = os.files("*.cc")
            lib_files = table.filter(lib_files, function(f) 
                return not f:match("_test%.cc$") and not f:match("_plugin%.cc$")
            end)
            add_files(table.unpack(lib_files))
            
            -- Same includes/links as main library
            add_includedirs(".", 
                "$(projectdir)/include",
                "$(projectdir)/thirdparty/nccl/build/include")
            
            local cuda_home = (os.getenv("CUDA_HOME") or "/usr/local/cuda")
            add_includedirs(cuda_home .. "/include")
            add_linkdirs(cuda_home .. "/lib64")
            add_links("ibverbs", "cudart", "gtest", "z", "elf", "pthread")
            add_cxxflags("-O3", "-std=c++17", "-Wno-pointer-arith", "-Wno-interference-size")
        target_end()
    end
end