-- ============================================================================
-- P2P Engine (C++ core + Python nanobind bindings)
-- ============================================================================

-- ============================================================================
-- OPTIONS (mirror Makefile flags)
-- ============================================================================

option("use_tcpx")
    set_default(false)
    set_description("Enable TCPX transport")
option_end()

option("use_efa")
    set_default(false)
    set_description("Enable EFA transport")
option_end()

option("use_tcp")
    set_default(false)
    set_description("Enable NCCL-over-TCP endpoint")
option_end()

option("use_dietgpu")
    set_default(false)
    set_description("Enable DietGPU compression")
option_end()

-- ============================================================================
-- COMMON RULE
-- ============================================================================

rule("p2p.base")
    on_load(function (target)
        local p2p_dir = os.scriptdir()

        target:add("includedirs",
            p2p_dir,
            path.join(p2p_dir, "include"),
            {public = true}   -- 🔥 important for reuse
        )

        target:add("cxxflags",
            "-O3",
            "-fPIC",
            "-MMD",
            "-Wno-pointer-arith",
            "-Wno-sign-compare",
            "-Wno-unused-variable"
        )

        target:add("packages", "python")
        target:add("packages", "nanobind")
    end)
rule_end()

function apply_p2p_features(target)
    if get_config("use_tcpx") then
        target:add("defines", "UCCL_P2P_USE_TCPX")
    elseif get_config("use_efa") then
        target:add("defines", "UCCL_P2P_USE_EFA")
        target:add("includedirs", "/opt/amazon/efa/include")
        target:add("linkdirs", "/opt/amazon/efa/lib")
        target:add("links", "efa")
    end

    if get_config("use_tcp") then
        target:add("defines", "UCCL_P2P_USE_NCCL")
    end

    if get_config("use_dietgpu") then
        local root = "../thirdparty/dietgpu"
        target:add("defines", "USE_DIETGPU")
        target:add("includedirs", root)
        target:add("linkdirs", path.join(root, "dietgpu/float"))
        target:add("links", "dietgpu_float")
        target:add("rpathdirs", path.join(root, "dietgpu/float"))
    end
end

-- ============================================================================
-- CORE LIBRARY
-- ============================================================================

target("uccl_p2p_core")
    set_kind("shared")  -- matches libuccl_p2p.so
    set_targetdir("$(builddir)/lib")

    add_rules("uccl.common", "uccl.backend", "p2p.base")

    apply_p2p_features(target)

    -- this is as in the makefile, leave commented out.
    if get_config("use_tcpx") then
        add_files("nccl_tcpx_endpoint.cc")
        set_basename("uccl_p2p_tcpx")
    elseif get_config("use_tcp") then
        add_files("engine.cc", "engine_api.cc", "nccl/nccl_endpoint.cc")
        set_basename("uccl_p2p_tcp")
    else
        add_files("engine.cc", "engine_api.cc")
        set_basename("uccl_p2p")
    end

    add_files("uccl_engine.cc")

-- ============================================================================
-- PYTHON BINDINGS (nanobind)
-- ============================================================================

-- target("uccl_p2p_py")
--     set_kind("shared")
--     set_targetdir("$(builddir)/python")

--     add_rules("uccl.common", "uccl.backend", "ccl.p2p")

--     add_deps("uccl_p2p_core")

--     -- nanobind detection
--     on_load(function (target)
--         import("lib.detect.find_program")

--         local python = find_program("python3")
--         assert(python, "python3 not found")

--         -- nanobind include path
--         local nb_dir = os.iorunv(python, {
--             "-c",
--             "import nanobind, os; print(os.path.dirname(nanobind.__file__))"
--         }):trim()

--         local py_include = os.iorunv(python, {
--             "-c",
--             "import sysconfig; print(sysconfig.get_path('include'))"
--         }):trim()

--         target:add("includedirs",
--             path.join(nb_dir, "include"),
--             path.join(nb_dir, "ext/robin_map/include"),
--             py_include
--         )

--         -- Stable ABI detection
--         local abi_ok = os.iorunv(python, {
--             "-c",
--             "import sys; print(1 if sys.version_info >= (3,12) else 0)"
--         }):trim()

--         if abi_ok == "1" then
--             target:add("defines",
--                 "Py_LIMITED_API=0x030C0000",
--                 "NB_STABLE_ABI=1"
--             )
--             target:set("extension", ".abi3.so")
--         end
--     end)

--     -- nanobind sources
--     local nb_src = {
--         "nb_internals.cpp",
--         "nb_func.cpp",
--         "nb_type.cpp",
--         "nb_enum.cpp",
--         "nb_ndarray.cpp",
--         "nb_static_property.cpp",
--         "common.cpp",
--         "error.cpp",
--         "trampoline.cpp",
--         "implicit.cpp"
--     }

--     for _, f in ipairs(nb_src) do
--         add_files(path.join("$(projectdir)", "thirdparty/nanobind/src", f))
--     end

--     -- your binding sources
--     if get_config("use_tcpx") then
--         add_files("nccl_tcpx_endpoint.cc")
--     elseif get_config("use_tcp") then
--         add_files("engine.cc", "engine_api.cc", "nccl/nccl_endpoint.cc")
--     else
--         add_files("engine.cc", "engine_api.cc")
--     end

--     set_basename("p2p")

-- -- ============================================================================
-- -- INSTALL
-- -- ============================================================================

-- target("p2p_install")
--     set_kind("phony")

--     on_run(function ()
--         import("lib.detect.find_program")

--         local python = find_program("python3")
--         local site = os.iorunv(python, {
--             "-c",
--             "import site; print(site.getsitepackages()[0])"
--         }):trim()

--         local install_dir = path.join(site, "uccl")
--         os.mkdir(install_dir)

--         os.cp("$(builddir)/python/p2p*.so", install_dir)

--         print("Installed Python module to: " .. install_dir)
--     end)