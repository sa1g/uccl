local backend = get_config("backend") or "cuda"
local use_intel_rdma_nic = get_config("use_intel_rdma_nic")

local is_cuda = get_config("is_cuda")
local is_rocm = get_config("is_rocm")
local is_therock = get_config("therock")

local plugin_name = is_cuda and "libnccl-net-uccl.so" or "librccl-net-uccl.so"
local target_basename = is_cuda and "nccl-net-uccl" or "rccl-net-uccl"

local cxxflags_common = {
    "-O3",
    "-g",
    "-std=c++17",
    "-Wno-pointer-arith",
    "-Wno-interference-size",
    "-fPIC",
}

--------------------------------------------------------
-- Core library (static)
--------------------------------------------------------
target("ccl_rdma_core")
    set_kind("static")
    set_targetdir("$(builddir)/lib")

    -- add_packages("nccl_headers")
    add_deps("util")

    if is_cuda then 
    end

    -- Sources
    add_files("*.cc")
    remove_files("*_main.cc")
    remove_files("*_test.cc")

    -- Defines
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

    -- Links
    add_links("ibverbs")
    if is_cuda then 
        add_packages("nccl_headers")
    end
    if is_cuda and use_intel_rdma_nic then
        add_links("cudart", "cuda")
    end

    add_cxxflags(table.unpack(cxxflags_common))

--------------------------------------------------------
-- Plugin (C++ shared library)
--------------------------------------------------------
target("ccl_rdma_plugin")
    set_kind("shared")
    set_basename(target_basename)
    set_targetdir("$(builddir)/lib")

    add_deps("ccl_rdma_core")

    add_files("*_plugin.cc")

    add_ldflags("-Wl,-soname," .. plugin_name)

    -- Defines
    if is_cuda then
        add_defines("USE_CUDA")
        add_rules("cuda")
        set_policy("build.cuda.devlink", true)
    elseif is_rocm then
        add_defines("USE_ROCM")
    end

    if use_intel_rdma_nic then
        add_defines("INTEL_RDMA_NIC", "MTU_4096")
    end

    -- Links
    add_links("ibverbs")
    if is_cuda then 
        add_packages("nccl_headers")
    end
    if is_cuda and use_intel_rdma_nic then
        add_links("cudart", "cuda")
    end

    add_cxxflags(table.unpack(cxxflags_common))
