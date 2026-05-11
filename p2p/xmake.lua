-- ============================================================================
-- P2P Engine (C++ shared library)
-- ============================================================================

option("use_dietgpu")
    set_default(false)
    set_description("Enable DietGPU compression")
option_end()

rule("p2p.base")
    on_load(function (target)
        local p2p_dir = os.scriptdir()
        local project_dir = path.join(p2p_dir, "..")
        local cuda_home = os.getenv("CUDA_HOME") or "/usr/local/cuda"
        local efa_home = os.getenv("EFA_HOME") or "/opt/amazon/efa"

        target:add("includedirs",
            p2p_dir,
            path.join(p2p_dir, "include"),
            path.join(project_dir, "include"),
            cuda_home .. "/include",
            efa_home .. "/include",
            {public = true}
        )

        target:add("linkdirs", cuda_home .. "/lib64")
        target:add("links", "cudart", "cuda", "pthread", "z", "elf", "dl")
        target:add("ldflags",
            "-Wl,--wrap=ibv_get_device_list",
            "-Wl,--wrap=ibv_query_port",
            "-Wl,--wrap=ibv_reg_mr",
            "-Wl,--wrap=ibv_reg_dmabuf_mr",
            "-Wl,--wrap=ibv_create_cq",
            "-Wl,--wrap=ibv_create_qp",
            "-Wl,--wrap=ibv_qp_to_qp_ex"
        )

        target:add("cxxflags",
            "-O3",
            "-fPIC",
            "-Wno-pointer-arith",
            "-Wno-sign-compare",
            "-Wno-unused-variable"
        )

        target:add("packages", "python")
        target:add("packages", "nanobind")
    end)
rule_end()

target("uccl_p2p_core")
    set_kind("shared")
    set_targetdir("$(builddir)/lib")
    set_basename("uccl_p2p")

    add_rules("uccl.backend", "p2p.base")

    add_files(
        "engine.cc",
        "uccl_engine.cc",
        "nccl/nccl_endpoint.cc",
        "rdma/ibverbs_dl.cc",
        "nccl/nccl_dl.cc",
        "rdma/efadv_dl.cc"
    )