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
--   xmake build p2p               # Build the P2P shared library
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
    -- set_symbols("debug")
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

package("nccl")
    set_description("NVIDIA Collective Communications Library")
    set_homepage("https://developer.nvidia.com/nccl")
    set_license("MIT")
    add_configs("shared", {description = "Use shared library", default = true, type = "boolean"})

    on_load(function(package)
        if not is_plat("linux") then
            raise("nccl is only supported on Linux")
        end

        -- Prefer NCCL shipped with NVHPC when available
        local nvhpc_root = os.getenv("NVHPC_ROOT")
        if nvhpc_root then
            local nvhpc_nccl = path.join(nvhpc_root, "comm_libs", "nccl")
            if os.isdir(nvhpc_nccl) then
                package:set("installdir", nvhpc_nccl)
                return
            end
        end

        -- Check for CUDA path (common location for NCCL)
        local cuda_path = os.getenv("CUDA_PATH") or os.getenv("CUDA_HOME") or "/usr/local/cuda"
        local cuda_nccl = path.join(cuda_path, "targets", "x86_64-linux")
        if os.isdir(path.join(cuda_nccl, "include", "nccl.h")) then
            package:set("installdir", cuda_nccl)
            return
        end

        -- Try well-known system paths as fallback
        local system_paths = {
            "/usr",
            "/usr/local",
        }
        
        for _, syspath in ipairs(system_paths) do
            if os.isdir(path.join(syspath, "include", "nccl.h")) then
                package:set("installdir", syspath)
                return
            end
        end
    end)

    on_fetch(function(package)
        import("lib.detect.find_package")

        -- First try pkg-config if available (handles Debian/Arch system packages)
        local pkg_config_result = nil
        local has_pkg_config = os.isfile("/usr/bin/pkg-config") or os.isfile("/usr/local/bin/pkg-config") or os.getenv("PKG_CONFIG_PATH")
        
        if has_pkg_config then
            pkg_config_result = find_package("nccl", {pkgconfig = "nccl"})
            if pkg_config_result then
                print("nccl found via pkg-config")
                return pkg_config_result
            end
        end

        -- Try system package detection
        local system_result = find_package("nccl", {
            system = true,
            links = "nccl",
            configs = {shared = package:config("shared")}
        })
        
        if system_result then
            print("nccl found in system, %s", table.concat(system_result.linkdirs or {}, ", "))
            return system_result
        end

        -- Manual detection in installdir
        local installdir = package:installdir()
        if not installdir or not os.isdir(installdir) then
            raise("nccl not found - please install NCCL via system package manager (e.g., 'sudo apt install libnccl2 libnccl-dev' on Debian/Ubuntu, 'sudo pacman -S nccl' on Arch) or set NVHPC_ROOT/CUDA_PATH")
        end

        -- Determine include path
        local includedirs = {}
        local possible_include_dirs = {
            path.join(installdir, "include"),
            path.join(installdir, "targets", "x86_64-linux", "include"),
        }
        
        for _, incdir in ipairs(possible_include_dirs) do
            if os.isdir(incdir) and os.isfile(path.join(incdir, "nccl.h")) then
                table.insert(includedirs, incdir)
                break
            end
        end

        -- Determine library paths
        local libdirs = {
            path.join(installdir, "lib"),
            path.join(installdir, "lib64"),
            path.join(installdir, "lib", "x86_64-linux-gnu"),
            path.join(installdir, "targets", "x86_64-linux", "lib"),
        }

        local linkdirs = {}
        local links = {}
        local want_shared = package:config("shared") ~= false
        local shared_names = {"libnccl.so", "libnccl.so.2", "libnccl.so.2.0.0"}
        local static_name = "libnccl.a"

        for _, dir in ipairs(libdirs) do
            if os.isdir(dir) then
                if want_shared then
                    for _, shared_name in ipairs(shared_names) do
                        if os.isfile(path.join(dir, shared_name)) then
                            table.insert(linkdirs, dir)
                            table.insert(links, "nccl")
                            break
                        end
                    end
                    if #links > 0 then break end
                elseif os.isfile(path.join(dir, static_name)) then
                    table.insert(linkdirs, dir)
                    table.insert(links, "nccl")
                    break
                end
            end
        end

        if #links > 0 and #includedirs > 0 then
            print("nccl found in %s", installdir)
            return {
                includedirs = includedirs,
                linkdirs = linkdirs,
                links = links
            }
        end

        -- Error with helpful message
        raise("nccl not found in %s (checked:\n  includes: %s\n  libs: %s)", 
              installdir, 
              table.concat(possible_include_dirs, ", "), 
              table.concat(libdirs, ", "))
    end)
package_end()

add_requires("gtest", "gflags", {optional = true})

add_requires("python 3.14.3")
add_requires("nanobind 2.12.0", {
    configs = {python = true}
})

if get_config("backend") == "cuda" then 
    add_requires("nccl_headers")
    add_requires("nccl")
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
