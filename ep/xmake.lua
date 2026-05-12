-- -- GPU-Driven EP Engine with optional Python bindings
-- -- Pure C++ CUDA kernel + Python nanobind wrapper

-- local backend = get_config("backend")
-- local build_tests = get_config("build_tests")
-- local use_intel_rdma_nic = get_config("use_intel_rdma_nic")

-- -- Skip on therock (no GPU-driven support yet)
-- if backend == "therock" then
--     function on_load()
--         print("[ep] Skipping GPU-driven build on therock")
--         set_kind("phony")
--     end
--     return
-- end

-- -- CUDA architecture detection
-- local function get_cuda_arch()
--     return os.iorun("nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n1 | tr -d ' ' | sed 's/\\.//g'"):trim()
-- end

-- -- ============================================================================
-- -- PHASE 1: Pure C++ + CUDA Kernel Compilation
-- -- ============================================================================

-- target("ep_lib")
--     set_kind("shared")
--     set_targetdir("$(builddir)/lib")
    
--     -- C++ sources
--     add_files("src/proxy.cpp", "src/rdma.cpp", "src/common.cpp", 
--               "src/uccl_proxy.cpp", "src/uccl_bench.cpp", "src/fifo.cpp")
    
--     -- CUDA kernels
--     add_files("src/bench_kernel.cu", "src/internode_ll.cu", "src/internode.cu",
--               "src/layout.cu", "src/intranode.cu", "src/ep_runtime.cu")
    
--     add_includedirs("include", "$(projectdir)/include", ".")
    
--     -- CUDA Setup
--     local cuda_home = (os.getenv("CUDA_HOME") or "/usr/local/cuda")
--     add_includedirs(cuda_home .. "/include")
--     add_linkdirs(cuda_home .. "/lib64")
    
--     -- Torch dependencies
--     local torch_root = os.iorun("python3 -c \"import torch, pathlib; print(pathlib.Path(torch.__file__).parent)\""):trim()
--     add_includedirs(torch_root .. "/include", 
--                    torch_root .. "/include/torch/csrc/api/include")
--     add_linkdirs(torch_root .. "/lib")
    
--     -- GPU architecture
--     local sm = get_cuda_arch() or "90"
--     add_nvccflags("-gencode=arch=compute_" .. sm .. ",code=sm_" .. sm)
    
--     add_links("cudart", "cuda", "ibverbs", "pthread", "lnl-3", "lnl-route-3", "numa")
    
--     add_cxxflags("-O3", "-std=c++17", "-fPIC", "-fvisibility=hidden")
--     add_nvccflags("-O3", "-std=c++17", "-Xcompiler \"-fPIC -fvisibility=hidden\"")
    
--     -- Feature flags
--     if use_intel_rdma_nic then
--         add_defines("INTEL_RDMA_NIC")
--     end
    
--     on_install(function(target)
--         os.mkdir("$(projectdir)/uccl/lib")
--         os.cp(target:targetfile(), "$(projectdir)/uccl/lib/")
--     end)
-- target_end()

-- -- ============================================================================
-- -- PHASE 2: Python Bindings (Torch-based)
-- -- ============================================================================

-- local python = os.getenv("PYTHON") or "python3"
-- local py_stable_abi = os.iorun(python .. " -c \"import sys; print(1 if sys.version_info >= (3, 12) else 0)\""):trim() == "1"
-- local py_ext = py_stable_abi and ".abi3.so" or ".so"

-- target("ep_py")
--     set_kind("shared")
--     set_targetdir("$(builddir)")
    
--     -- Only nanobind sources
--     add_files("src/uccl_ep.cc")
    
--     add_includedirs("include", ".", "$(projectdir)/include")
    
--     -- Torch
--     local torch_root = os.iorun("python3 -c \"import torch, pathlib; print(pathlib.Path(torch.__file__).parent)\""):trim()
--     add_includedirs(torch_root .. "/include",
--                    torch_root .. "/include/torch/csrc/api/include")
--     add_linkdirs(torch_root .. "/lib")
    
--     -- nanobind
--     local nb_dir = os.iorun(python .. " -c \"import nanobind as _nb, os; print(os.path.dirname(_nb.__file__))\""):trim()
--     local py_include = os.iorun(python .. " -c \"import sysconfig; print(sysconfig.get_path('include'))\""):trim()
    
--     add_includedirs(nb_dir .. "/include",
--                    nb_dir .. "/ext/robin_map/include",
--                    py_include)
    
--     -- Link against ep_lib
--     add_deps("ep_lib")
--     add_linkdirs("$(builddir)/lib")
--     add_links("uccl_ep_lib")
    
--     local cuda_home = (os.getenv("CUDA_HOME") or "/usr/local/cuda")
--     add_includedirs(cuda_home .. "/include")
--     add_linkdirs(cuda_home .. "/lib64")
--     add_links("cudart", "cuda")
    
--     if py_stable_abi then
--         add_cxxflags("-DPy_LIMITED_API=0x030C0000", "-DNB_STABLE_ABI=1")
--     end
    
--     add_cxxflags("-O3", "-std=c++17", "-fPIC", "-shared", "-fvisibility=hidden")
    
--     on_install(function(target)
--         os.mkdir("$(projectdir)/uccl/")
--         local ext = py_stable_abi and ".abi3.so" or (os.iorun(python .. " -c \"import sysconfig; print(sysconfig.get_config_var('EXT_SUFFIX'))\""):trim())
--         os.cp(target:targetfile(), "$(projectdir)/uccl/ep" .. ext)
--     end)
-- target_end()

-- -- ============================================================================
-- -- Tests & Benchmarks (optional)
-- -- ============================================================================

-- if build_tests then
--     for _, test_file in ipairs(os.files("*_test.cc")) do
--         local test_name = test_file:match("([^/]+)_test%.cc$")
--         target("ep_test_" .. test_name)
--             set_kind("binary")
--             set_targetdir("$(builddir)/tests")
--             add_files(test_file)
--             add_includes("include", "$(projectdir)/include")
--             add_linkdirs("$(builddir)/lib")
--             add_links("uccl_ep_lib", "gtest", "pthread")
--             add_cxxflags("-O3", "-std=c++17", "-DGTEST_HAS_PTHREAD=1")
--         target_end()
--     end
-- end