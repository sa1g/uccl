-- set_project("uccl_p2p")
-- set_languages("cxx20")

add_rules("mode.debug", "mode.release")

-- ----------------------------------------------------------------------------
-- Options
-- ----------------------------------------------------------------------------

option("dietgpu")
    set_default(false)
    set_showmenu(true)
    set_description("Enable DietGPU compression")
option_end()

if has_config("dietgpu") then
    print("DietGPU support is currently disabled due to libtorch compilation issues. Please check the documentation for updates.")
end

-- ----------------------------------------------------------------------------
-- Custom Packages
-- ----------------------------------------------------------------------------

package("dietgpu")
    set_kind("library")
    set_homepage("https://github.com/facebookresearch/dietgpu")
    set_description("DietGPU compression library for GPU tensors")

    set_urls("https://github.com/facebookresearch/dietgpu.git")
    add_versions("latest", "a4d70a14066d2c3e5fe1849b3723e4cd423eee7e")

    add_deps("cmake", "libtorch")

    on_install(function (package)
        import("package.tools.cmake")

        cmake.install(package, {
            "-DBUILD_SHARED_LIBS=ON"
        })
    end)

    on_load(function (package)
        package:add("links", "dietgpu_float")
    end)
package_end()

-- ----------------------------------------------------------------------------
-- Dependencies
-- ----------------------------------------------------------------------------

add_requires("cuda")
add_requires("python")
add_requires("nanobind")

-- if has_config("dietgpu") then
--     add_requires("dietgpu::a4d70a14", {system = false, external = false})
-- end

-- ----------------------------------------------------------------------------
-- CUDA Configuration
-- ----------------------------------------------------------------------------

toolchain("cuda")
    set_kind("standalone")
toolchain_end()

-- ----------------------------------------------------------------------------
-- Common Rule
-- ----------------------------------------------------------------------------

rule("p2p.common")
    on_load(function (target)

        local rootdir = os.scriptdir()
        local projectdir = path.join(rootdir, "..")

        target:add("includedirs",
            rootdir,
            path.join(rootdir, "include"),
            path.join(projectdir, "include"),
            {public = true}
        )

        target:add("syslinks",
            "pthread",
            "dl",
            "z",
            "elf"
        )

        target:add("packages",
            "cuda",
            "python",
            "nanobind"
        )

        target:add("cxflags",
            "-Wno-pointer-arith",
            "-Wno-sign-compare",
            "-Wno-unused-variable"
        )

        target:add("ldflags",
            "-Wl,--wrap=ibv_get_device_list",
            "-Wl,--wrap=ibv_query_port",
            "-Wl,--wrap=ibv_reg_mr",
            "-Wl,--wrap=ibv_reg_dmabuf_mr",
            "-Wl,--wrap=ibv_create_cq",
            "-Wl,--wrap=ibv_create_qp",
            "-Wl,--wrap=ibv_qp_to_qp_ex",
            {force = true}
        )

        -- if has_config("dietgpu") then
        --     target:add("packages", "dietgpu")
        --     target:add("defines", "USE_DIETGPU")
        -- end
    end)
rule_end()

-- ----------------------------------------------------------------------------
-- Target
-- ----------------------------------------------------------------------------

target("uccl_p2p")
    set_kind("shared")
    set_targetdir("$(builddir)/lib")

    add_rules(
        "p2p.common",
        "uccl.backend"
    )

    set_toolchains("cuda")

    add_files(
        "engine.cc",
        "uccl_engine.cc",
        "nccl/nccl_endpoint.cc",
        "rdma/ibverbs_dl.cc",
        "nccl/nccl_dl.cc",
        "rdma/efadv_dl.cc"
    )

    -- Native CUDA arch handling
    add_cugencodes("native")

    set_optimize("fastest")
    set_symbols("hidden")