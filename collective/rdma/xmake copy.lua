
local backend = get_config("backend") or "cuda"
local use_intel_rdma_nic = get_config("use_intel_rdma_nic")

local is_cuda = (backend == "cuda")
local is_rocm = (backend == "rocm" or backend == "rocm6")
local is_therock = (backend == "therock")

if not (is_cuda or is_rocm or is_therock) then
    raise("Unsupported backend for collective/rdma: " .. tostring(backend))
end

local rdma_root = os.scriptdir()
local repo_root = path.absolute(path.join(rdma_root, "../.."))

local cuda_home = os.getenv("CUDA_HOME") or "/usr/local/cuda"
local hip_home = os.getenv("HIP_HOME") or "/opt/rocm"
local conda_lib_home = os.getenv("CONDA_LIB_HOME") or "/usr/lib"

local plugin_name = is_cuda and "libnccl-net-uccl.so" or "librccl-net-uccl.so"
local target_basename = is_cuda and "nccl-net-uccl" or "rccl-net-uccl"

if is_cuda then
    add_requires("nccl", {system = true})
    add_requires("cuda", {system = true})
else
    add_requires("rccl", {system = true})
end

local lib_src = os.files(path.join(rdma_root, "*.cc"))
lib_src = table.filter(lib_src, function(f)
    return not f:match("_main%.cc$")
       and not f:match("_test%.cc$")
       and not f:match("_plugin%.cc$")
end)

target("ccl_rdma")
    set_kind("shared")
    set_targetdir("$(builddir)/lib")
    set_basename(target_basename)

    add_files(path.join(rdma_root, "nccl_plugin.cc"))
    if #lib_src > 0 then
        add_files(table.unpack(lib_src))
    end

    add_includedirs(
        rdma_root,
        path.join(repo_root, "include")
    )

    if is_cuda then
        add_includedirs(
            path.join(cuda_home, "include"),
            path.join(repo_root, "thirdparty/nccl/build/include"),
            path.join(repo_root, "thirdparty/nccl/src/include")
        )
    else
        add_includedirs(
            path.join(hip_home, "include"),
            path.join(conda_lib_home, "../include"),
            path.join(repo_root, "thirdparty/rccl/build/release/include"),
            path.join(repo_root, "thirdparty/rccl/src/include")
        )
        add_linkdirs(conda_lib_home)
    end

    add_links("gflags", "gtest", "z", "elf", "ibverbs", "pthread")
    if not is_cuda then
        add_links("dl")
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

    if is_cuda then
        add_defines("USE_CUDA")
        if use_intel_rdma_nic or os.getenv("USE_INTEL_RDMA_NIC") == "1" then
            add_defines("INTEL_RDMA_NIC")
        end
    else
        add_defines("__HIP_PLATFORM_AMD__")
    end

    add_ldflags("-Wl,-soname," .. plugin_name)
target_end()