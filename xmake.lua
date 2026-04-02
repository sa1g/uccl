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

-- set_xmakever("2.7.2")

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
if is_mode("debug") then
    set_symbols("debug")
    set_optimize("none")
else
    -- set_symbols("hidden")
    set_optimize("fastest")
    set_strip("all")
end

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

add_requires("gtest", "gflags")

-- Required for Python bindings - p2p
add_requires("python", {system = true})
add_requires("nanobind 2.12.0", {configs = {python = true}})

if get_config("backend") == "cuda" then 
    add_requires("nccl_headers")
    add_requires("nccl", {system = true})
    add_rules("cuda", {system = true})
end

-- ============================================================================
-- RULES
-- ============================================================================

rule("uccl.backend")
    on_config(function (target)
        if get_config("backend") == "cuda" then
            target:add("packages", "nccl_headers")
            target:add("defines", "USE_CUDA")
        else
            target:add("defines", "USE_ROCM")
        end
    end)
rule_end()

rule("uccl.common")
    on_load(function (target)
        target:add("deps", "util")
        target:add("links", "ibverbs")

        if get_config("use_intel_rdma_nic") then
            target:add("defines", "USE_INTEL_RDMA_NIC=1")
        end
    end)
rule_end()

-- ============================================================================
-- SET GLOBAL CONFIG
-- ============================================================================
set_languages("c++17")

-- ============================================================================
-- INCLUDE COMPONENT TARGETS
-- ============================================================================

-- Include subdirectories with their own xmake.lua files
includes("include")
includes("collective/rdma/")
-- includes("collective/efa")
includes("p2p")
-- includes("ep")
-- includes("experimental/ukernel")
