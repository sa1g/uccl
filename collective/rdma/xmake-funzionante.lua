local is_cuda = get_config("is_cuda")
local is_rocm = get_config("is_rocm")
local is_therock = get_config("therock")

local plugin_name = is_cuda and "libnccl-net-uccl.so" or "librccl-net-uccl.so"
local target_basename = is_cuda and "nccl-net-uccl" or "rccl-net-uccl"

target("ccl_rdma")
    set_kind("shared")
    add_deps("util", {public = true})
    set_targetdir("$(builddir)/lib")
    set_basename(target_basename)
    
    add_files("*.cc")
    remove_files("*_main.cc")
    remove_files("*_test.cc")
   
    if is_cuda then
        add_rules("cuda")
        add_defines("USE_CUDA")
        add_cuflags(
            "-O3",
            "-std=c++17",
            "-Wno-pointer-arith",
            "-Wno-interference-size"
        )
    else
        add_defines("USE_ROCM")
    end
    
    add_defines("USE_INTEL_RDMA_NIC=" .. (use_intel_rdma_nic and "1" or "0"))
    
    add_links("gflags", "gtest", "z", "elf", "ibverbs", "pthread")
    
    if is_cuda and use_intel_rdma_nic then
        add_links("cudart", "cuda")
    end
    
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
    
    add_ldflags("-Wl,-soname," .. plugin_name)
    
    if is_cuda then
        set_policy("build.cuda.devlink", true)
    end

target_end()