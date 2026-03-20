-- UCCL Build System - Restructured for modular C++/Python separation
-- 
-- Build modes:
--   xmake build [target]          - Build C++ libraries only
--   xmake build [target]_py       - Build Python bindings (depends on C++ lib)
--   xmake build --tests           - Build tests/benchmarks
--   xmake build --wheel           - Full wheel assembly
--
-- Examples:
--   xmake config --backend=cuda --build_type=all
--   xmake build                   # Build all C++ libs
--   xmake build p2p_py            # Build P2P library + bindings
--   xmake build --tests p2p_test  # Build P2P tests only
--

set_xmakever("2.7.2")

-- Rules
add_rules("mode.debug", "mode.release")

-- ============================================================================
-- OPTIONS & CONFIGURATION
-- ============================================================================

option("backend")
    set_default("cuda")
    set_values("cuda", "rocm", "rocm6", "therock")
    set_description("Compute backend: cuda, rocm, rocm6, therock")
    set_showmenu(true)
option_end()

option("is_efa")
    set_showmenu(true)
    set_description("Enable EFA support (auto-detected from system)")
    on_check(function (option)
        -- Try to detect EFA by checking for InfiniBand/RDMA devices
        local has_efa = false
        
        -- Check if /sys/class/infiniband/ exists and contains rdmap devices
        import("lib.detect.find_directory")
        import("lib.detect.find_file")
        
        local infiniband_path = "/sys/class/infiniband/"
        if find_directory(infiniband_path) then
            -- Look for rdmap devices in the infiniband directory
            local files = os.files(path.join(infiniband_path, "*"))
            for _, file in ipairs(files) do
                local device_name = path.basename(file)
                -- Check if this device supports rdmap (simplified check)
                if device_name:find("rdma") or device_name:find("efa") then
                    has_efa = true
                    break
                end
            end
        end
        
        -- Also check if EFA kernel module is loaded (alternative method)
        if not has_efa then
            local modules = io.open("/proc/modules")
            if modules then
                local content = modules:read("*a")
                modules:close()
                if content:find("efa") or content:find("rdma") then
                    has_efa = true
                end
            end
        end
        
        -- Set the option value based on detection
        if has_efa then
            option:set_value(true)
            print("  EFA support: detected (enabled)")
        else
            option:set_value(false)
            print("  EFA support: not detected (disabled)")
        end
    end)
option_end()

-- Feature flags
option("use_efa")
    set_default(false)
    set_description("Enable EFA transport")
option_end()

option("use_ib")
    set_default(false)
    set_description("Enable InfiniBand transport")
option_end()

option("use_tcp")
    set_default(false)
    set_description("Enable TCP transport")
option_end()

option("use_dietgpu")
    set_default(false)
    set_description("Enable DietGPU compression")
option_end()

option("use_intel_rdma_nic")
    set_default(false)
    set_description("Enable Intel RDMA NIC (irdma driver)")
option_end()

option("rocm_idx_url")
    set_default("")
    set_description("ROCm package index URL")
option_end()

option("wheel_dir")
    set_description("Output directory for wheels")
option_end()

option("uccl_local_version")
    set_default("")
    set_description("Local version suffix for wheel (PEP 440)")
option_end()

-- ============================================================================
-- LOAD CONFIGURATION
-- ============================================================================
local backend = get_config("backend") or "cuda"

local is_efa = get_config("is_efa")
local use_efa = get_config("use_efa")
local use_ib = get_config("use_ib")
local use_tcp = get_config("use_tcp")
local use_dietgpu = get_config("use_dietgpu")
local use_intel_rdma_nic = get_config("use_intel_rdma_nic")
local rocm_idx_url = get_config("rocm_idx_url")
local wheel_dir = get_config("wheel_dir")
local uccl_local_version = get_config("uccl_local_version")

set_config("is_cuda", (backend) == "cuda")
set_config("is_rocm", (backend) == "rocm" or (backend) == "rocm6")
set_config("is_therock", (backend) == "therock")

local is_cuda = get_config("is_cuda")
local is_rocm = get_config("is_rocm")
local is_therock = get_config("is_therock")

-- ======
-- Manage CUDA/ROCm specific config
-- ======

package("nccl_headers")
    set_kind("library", {headeronly = true})

    set_homepage("https://developer.nvidia.com/nccl")
    set_description("NVIDIA Collective Communications Library (NCCL) - headers only")

    set_urls("https://github.com/NVIDIA/nccl/archive/$(version).zip", {excludes = {"ext*", "pkg/"}})

    add_versions("v2.23.4-1", "ab90848ac0fe614b62b20108079b0edc777a66d91e4e2d1150222841fefaff4a")

    on_install(function (package)
        -- Headers-only, just copy headers
        os.cp("src/include/*", package:installdir("include"))
    end)
package_end()

if is_cuda then
    add_requires("nccl_headers")
    add_packages("nccl_headers")

    add_requires("cuda", {system = true})
    set_toolchains("cuda")
    add_cugencodes("native") 
else
    -- add_requires("rccl", {system = true})

    -- local rccl_home = path.join(os.projectdir(), "thirdparty/nccl")
    -- local hip_home = os.getenv("HIP_HOME") or "/opt/rocm"

    -- add_includedirs(
    --     path.join(rccl_home, "build/release/include"),
    --     path.join(rccl_home, "src/include") --,
    --     -- path.join(hip_home, "lib")
    -- )

    -- -- include libraries for ROCm (e.g., ROCm runtime, ROCm compiler)
    -- add_requires("hip", {system = true})
end

-- ============================================================================
-- INCLUDE COMPONENT TARGETS
-- ============================================================================

-- Include subdirectories with their own xmake.lua files
includes("include")
includes("collective/rdma/")
includes("collective/efa")
-- includes("p2p")
-- includes("ep")
-- includes("experimental/ukernel")

-- -- ============================================================================
-- -- COMPOSITE TARGETS
-- -- ============================================================================

-- -- Meta-target: p2p_ep builds both
-- target("p2p_ep")
--     set_kind("phony")
--     depends_on("p2p_lib")
--     depends_on("ep_lib")
-- target_end()

-- -- Meta-target: all (controlled by build_type option)
-- if build_type == "all" then
--     target("all")
--         set_kind("phony")
--         if use_efa then
--             depends_on("ccl_efa")
--         else
--             depends_on("ccl_rdma")
--         end
--         depends_on("p2p_lib")
--         depends_on("ep_lib")
--         depends_on("ukernel")
--     target_end()
-- elseif build_type == "ccl_rdma" then
--     target("all")
--         set_kind("phony")
--         depends_on("ccl_rdma")
--     target_end()
-- elseif build_type == "ccl_efa" then
--     target("all")
--         set_kind("phony")
--         depends_on("ccl_efa")
--     target_end()
-- elseif build_type == "p2p" then
--     target("all")
--         set_kind("phony")
--         depends_on("p2p_lib")
--     target_end()
-- elseif build_type == "ep" then
--     target("all")
--         set_kind("phony")
--         depends_on("ep_lib")
--     target_end()
-- elseif build_type == "ukernel" then
--     target("all")
--         set_kind("phony")
--         depends_on("ukernel")
--     target_end()
-- end

-- -- ============================================================================
-- -- WHEEL BUILD TARGET
-- -- ============================================================================

-- target("wheel")
--     set_kind("phony")
--     -- Ensure all C++ libs + bindings are built
--     depends_on("ccl_rdma")
--     -- depends_on("p2p_py")
--     -- depends_on("ep_py")
    
--     on_build(function(target)
--         print("[wheel] Building Python wheel...")
--         os.execv("python3", {"-m", "build"})
--     end)
-- target_end()
