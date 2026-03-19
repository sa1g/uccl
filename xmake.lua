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

option("arch")
    on_check(function (option)
        local detected_arch = os.arch()
        if detected_arch == "arm64" then
            option:set_value("aarch64")
            print("  Detected architecture: arm64 (using aarch64)")
        elseif detected_arch == "x86_64" then
            option:set_value("x86_64")
            print("  Detected architecture: x86_64")
        else
            print("  Warning: Unrecognized architecture '" .. detected_arch .. "'. Defaulting to x86_64.")
            option:set_value("x86_64")
        end
    end)
    set_values("x86_64", "aarch64", "arm64")
    set_description("Target architecture")
option_end()

option("build_type")
    set_default("all")
    set_values("all", "ccl_rdma", "ccl_efa", "p2p", "ep", "p2p_ep", "ukernel")
    set_description("What to build: all, ccl_rdma, ccl_efa, p2p, ep, p2p_ep, ukernel")
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

-- Build toggles
option("build_tests")
    set_default(false)
    set_description("Build test/benchmark binaries (not included in wheels)")
option_end()

option("build_wheel")
    set_default(false)
    set_description("Build wheel after C++ compilation")
option_end()

-- ============================================================================
-- LOAD CONFIGURATION
-- ============================================================================

local backend = get_config("backend") or "cuda"
local is_cuda = (backend == "cuda")
local arch = get_config("arch")
local build_type = get_config("build_type")
local py_ver = get_config("py_ver")
local is_efa = get_config("is_efa")
local use_efa = get_config("use_efa")
local use_ib = get_config("use_ib")
local use_tcp = get_config("use_tcp")
local use_dietgpu = get_config("use_dietgpu")
local use_intel_rdma_nic = get_config("use_intel_rdma_nic")
local rocm_idx_url = get_config("rocm_idx_url")
local wheel_dir = get_config("wheel_dir")
local uccl_local_version = get_config("uccl_local_version")
local build_tests = get_config("build_tests")
local build_wheel = get_config("build_wheel")

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- -- Determine Makefile variant based on backend
-- local function get_makefile_variant(suffix)
--     suffix = suffix or ""
--     if backend == "cuda" then
--         return "Makefile"
--     elseif backend:find("rocm") then
--         return "Makefile.rocm" .. suffix
--     elseif backend == "therock" then
--         return "Makefile.therock" .. suffix
--     end
--     return "Makefile" .. suffix
-- end

-- -- Build Make environment variables
-- local function get_make_env()
--     return {
--         USE_EFA = tostring(use_efa and 1 or 0),
--         USE_IB = tostring(use_ib and 1 or 0),
--         USE_TCP = tostring(use_tcp and 1 or 0),
--         USE_DIETGPU = tostring(use_dietgpu and 1 or 0),
--         USE_INTEL_RDMA_NIC = tostring(use_intel_rdma_nic and 1 or 0),
--     }
-- end

-- print("[xmake] Backend: " .. tostring(backend))
-- print("[xmake] Arch: " .. tostring(arch))
-- print("[xmake] Build type: " .. tostring(build_type))
-- print("[xmake] Build tests: " .. tostring(build_tests))

-- ============================================================================
-- INCLUDE COMPONENT TARGETS
-- ============================================================================

-- Include subdirectories with their own xmake.lua files
includes("include")
includes("collective/rdma/")
-- includes("collective/efa")
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

-- if build_wheel then
--     target("wheel")
--         set_kind("phony")
--         -- Ensure all C++ libs + bindings are built
--         depends_on("ccl_rdma")
--         depends_on("p2p_py")
--         depends_on("ep_py")
        
--         on_build(function(target)
--             print("[wheel] Building Python wheel...")
--             os.execv("python3", {"-m", "build"})
--         end)
--     target_end()
-- end