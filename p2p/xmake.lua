-- P2P Engine with optional Python bindings
-- Two-phase: 1) Pure C++ library, 2) Python bindings (conditional)

local backend = get_config("backend")
local use_tcp = get_config("use_tcp")
local use_efa = get_config("use_efa")
local use_dietgpu = get_config("use_dietgpu")
local build_tests = get_config("build_tests")

-- ============================================================================
-- PHASE 1: Pure C++ Library (NOT for Python wheel)
-- ============================================================================

target("p2p_lib")
    set_kind("shared")
    set_basename("libuccl_p2p")
    set_targetdir("$(builddir)/lib")
    
    -- Core library: exclude bindings and tests
    local lib_src = {
        "*.cc"
    }
    lib_src = table.filter(lib_src, function(f)
        local fullfile = os.files(f)[1] or f
        return not fullfile:match("_test%.cc$") and 
               not fullfile:match("_binding") and
               not fullfile:match("_py%.cc$") and
               not fullfile:match("uccl_ep%.cc$")
    end)
    add_files("*.cc")
    
    add_includedirs(".", "include", "$(projectdir)/include")
    
    -- CUDA
    local cuda_home = (os.getenv("CUDA_HOME") or "/usr/local/cuda")
    add_includedirs(cuda_home .. "/include")
    add_linkdirs(cuda_home .. "/lib64")
    add_links("cudart", "cuda")
    
    -- Conditional dependencies
    if use_tcp then
        add_defines("UCCL_P2P_USE_NCCL")
        local nccl_home = "$(projectdir)/thirdparty/nccl/build"
        add_includedirs(nccl_home .. "/include")
        add_linkdirs(nccl_home .. "/lib")
        add_links("nccl")
    end
    
    if use_efa then
        add_defines("UCCL_P2P_USE_EFA")
        local efa_home = (os.getenv("EFA_HOME") or "/opt/amazon/efa")
        add_includedirs(efa_home .. "/include")
        add_linkdirs(efa_home .. "/lib")
        add_links("efa")
    end
    
    if use_dietgpu then
        add_defines("USE_DIETGPU")
        add_includedirs("$(projectdir)/thirdparty/dietgpu")
        add_linkdirs("$(projectdir)/thirdparty/dietgpu/dietgpu/float")
        add_links("dietgpu_float")
    end
    
    add_links("ibverbs", "pthread", "z", "elf", "dl")
    add_cxxflags("-O3", "-shared", "-std=c++17", "-fPIC", "-Wno-pointer-arith")
    
    on_install(function(target)
        os.mkdir("$(projectdir)/uccl/lib")
        os.cp(target:targetfile(), "$(projectdir)/uccl/lib/")
    end)
target_end()

-- ============================================================================
-- PHASE 2: Python Bindings (nanobind, stable ABI)
-- Depends on p2p_lib, but only links for wheel export
-- ============================================================================

-- Detect Python config
local python = os.getenv("PYTHON") or "python3"

-- Helper to check Python stable ABI support
local function check_stable_abi()
    local result = os.iorun(python .. " -c \"import sys; print(1 if sys.version_info >= (3, 12) else 0)\""):trim()
    return result == "1"
end

local py_stable_abi = check_stable_abi()
local py_ext = py_stable_abi and ".abi3.so" or ".so"

target("p2p_py")
    set_kind("shared")
    set_basename("p2p" .. (py_stable_abi and "" or ""))
    set_targetdir("$(builddir)")
    add_includedirs(".") 
    
    -- Python binding source only
    add_files("p2p_binding.cc")  -- your nanobind file
    
    -- Get nanobind includes
    local nb_dir = os.iorun(python .. " -c \"import nanobind as _nb, os; print(os.path.dirname(_nb.__file__))\""):trim()
    local py_include = os.iorun(python .. " -c \"import sysconfig; print(sysconfig.get_path('include'))\""):trim()
    
    add_includedirs(
        nb_dir .. "/include",
        nb_dir .. "/ext/robin_map/include",
        py_include,
        "."
    )
    
    -- Depend on p2p_lib for symbols
    add_deps("p2p_lib")
    
    -- Link against built library
    add_linkdirs("$(builddir)/lib")
    add_links("uccl_p2p")
    
    -- Stable ABI flags
    if py_stable_abi then
        add_cxxflags("-DPy_LIMITED_API=0x030C0000", "-DNB_STABLE_ABI=1")
    end
    
    local cuda_home = (os.getenv("CUDA_HOME") or "/usr/local/cuda")
    add_includedirs(cuda_home .. "/include")
    add_linkdirs(cuda_home .. "/lib64")
    add_links("cudart")
    
    add_cxxflags("-O3", "-std=c++17", "-fPIC", "-shared")
    
    on_install(function(target)
        os.mkdir("$(projectdir)/uccl/")
        local ext = py_stable_abi and ".abi3.so" or (os.iorun(python .. " -c \"import sysconfig; print(sysconfig.get_config_var('EXT_SUFFIX'))\""):trim())
        os.cp(target:targetfile(), "$(projectdir)/uccl/p2p" .. ext)
    end)
target_end()

-- ============================================================================
-- Tests & Benchmarks (optional)
-- ============================================================================

if build_tests then
    for _, test_file in ipairs(os.files("*_test.cc")) do
        local test_name = test_file:match("([^/]+)_test%.cc$")
        target("p2p_test_" .. test_name)
            set_kind("binary")
            set_targetdir("$(builddir)/tests")
            add_files(test_file)
            
            -- Link against library
            add_deps("p2p_lib")
            add_includedirs(".", "include", "$(projectdir)/include")
            add_linkdirs("$(builddir)/lib")
            add_links("uccl_p2p", "gtest", "pthread", "z", "elf")
            
            add_cxxflags("-O3", "-std=c++17")
        target_end()
    end
end