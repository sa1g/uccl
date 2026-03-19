local backend = get_config("backend") or "cuda"
local use_intel_rdma_nic = get_config("use_intel_rdma_nic")

local is_cuda = (backend == "cuda")
local is_rocm = (backend == "rocm" or backend == "rocm6")
local is_therock = (backend == "therock")

if is_cuda then
    add_requires("nccl", {system = true})
    local nccl_home = path.join(os.projectdir(), "thirdparty/nccl")

    add_includedirs(
        path.join(nccl_home, "build/include"),
        path.join(nccl_home, "src/include")
    )

    -- Don't add "cuda" as a requirement, it's handled by the toolchain
    -- Instead, use the cuda package to get proper paths
    add_requires("cuda", {system = true})
    
    -- Set CUDA as the required toolchain
    set_toolchains("cuda")
    
    -- Add CUDA includes and links automatically
    add_cugencodes("native") -- Automatically detect GPU architecture

    
else
    add_requires("rccl", {system = true})
end

local plugin_name = is_cuda and "libnccl-net-uccl.so" or "librccl-net-uccl.so"
local target_basename = is_cuda and "nccl-net-uccl" or "rccl-net-uccl"

-- local project_root = os.projectdir()

target("ccl_rdma")
    set_kind("shared")
    add_deps("util", {public = true})
    set_targetdir("$(builddir)/lib")
    set_basename(target_basename)
    

    -- Add source files
    add_files("*.cc")
    remove_files("*_main.cc")
    remove_files("*_test.cc")
    -- remove_files("*_plugin.cc")
    
    -- Project includes
    -- add_includedirs(path.join(project_root, "include"))
    
    -- CUDA specific configuration
    if is_cuda then
        -- This will automatically use the detected CUDA paths
        -- add_packages("cuda")
        add_rules("cuda")

        
        -- Add CUDA includes (xmake handles this automatically, but if you need explicit)
        -- You can also add them manually if needed:
        -- local cuda_info = import("lib.detect.find_cuda")()
        -- if cuda_info and cuda_info.includedirs then
        --     add_includedirs(cuda_info.includedirs)
        -- end
        
        add_defines("USE_CUDA")
        
        -- If you need NVCC flags specifically
        add_cuflags(
            "-O3",
            "-std=c++17",
            "-Wno-pointer-arith",
            "-Wno-interference-size"
        )
        
        -- For mixed C++/CUDA code, specify which files are CUDA
        -- add_files("*.cu") -- If you have any .cu files
    else
        add_defines("USE_ROCM")
        -- Add ROCm specific configuration here
    end
    
    -- Common defines
    add_defines("USE_INTEL_RDMA_NIC=" .. (use_intel_rdma_nic and "1" or "0"))
    
    -- Common libraries
    add_links("gflags", "gtest", "z", "elf", "ibverbs", "pthread")
    
    -- If using RDMA with CUDA, you might need additional CUDA libraries
    if is_cuda and use_intel_rdma_nic then
        add_links("cudart", "cuda") -- Add CUDA runtime libraries
    end
    
    -- Common compiler flags
    add_cxxflags(
        "-O3",
        "-g",
        "-std=c++17",
        "-Wno-pointer-arith",
        "-Wno-interference-size",
        "-fPIC",
        "-MMD",
        "-MP"
    )
    
    -- Linker flags
    add_ldflags("-Wl,-soname," .. plugin_name)
    
    -- Build policy for device linking if using CUDA
    if is_cuda then
        set_policy("build.cuda.devlink", true) -- Enable device linking if needed
    end

target_end()