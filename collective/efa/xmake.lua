-- local is_cuda = get_config("is_cuda")

-- target("ccl_efa")
--     if not is_cuda then
--         on_load(function()
--             raise("EFA plugin requires CUDA backend. Please set backend=cuda.")
--         end)
--         return
--     end

--     set_policy("build.cuda.devlink", false)


--     set_kind("shared")
--     set_targetdir("$(builddir)/lib")
--     set_basename("nccl-net-efa")

--     add_deps("util")

--     -- Use system packages already declared at top-level
--     add_packages("cuda", "nccl")

--     local efa_home = os.getenv("EFA_HOME") or "/opt/amazon/efa"

--     -- Includes (CUDA/NCCL handled by add_packages)
--     add_includedirs(
--         path.join(efa_home, "include")
--     )

--     -- Sources
--     add_files("*.cc|*_main.cc|*_test.cc|*_plugin.cc")
--     add_files("scattered_memcpy.cu")

--     -- Link directories
--     add_linkdirs(path.join(efa_home, "lib"))

--     -- Link libraries
--     add_links(
--         "ibverbs",
--         "efa",
--         "pthread",
--         "gflags",
--         "z",
--         "elf"
--     )

--     -- CUDA runtime/libs come from toolchain/package,
--     -- but explicitly adding doesn't hurt if needed:
--     add_links("cudart", "cuda")

--     add_defines("USE_CUDA")

--     if get_config("use_intel_rdma_nic") then
--         add_defines("INTEL_RDMA_NIC", "MTU_4096")
--     end

--     add_cxxflags(
--         "-O3",
--         "-g",
--         "-std=c++17",
--         "-Wno-pointer-arith",
--         "-Wno-interference-size",
--         "-fPIC"
--         -- NOTE: -MMD/-MP not needed (Xmake handles deps)
--     )

--     add_rules("cuda")


-- target("ccl_efa_py")
--     -- set cuda linking to false
--     set_kind("shared")
--     set_basename("ccl_efa_py")
--     set_targetdir("$(builddir)/lib")
--     set_filename("ccl_efa_py.so")

--     set_policy("build.cuda.devlink", false)
--     add_deps("ccl_efa")



-- -- local is_cuda = get_config("is_cuda")

-- -- local plugin_name = "libnccl-net-efa.so"
-- -- local target_basename = "nccl-net-efa"

-- -- target("ccl_efa")
-- --     if not is_cuda then 
-- --         -- Skip EFA build if not using CUDA
-- --         -- Throw error to prevent downstream targets from building with missing dependency
-- --         on_load(function()
-- --             raise("EFA plugin requires CUDA backend. Please set backend=cuda to build this target.")
-- --         end)
-- --         return
-- --     end

-- --     set_kind("shared")
-- --     add_deps("util")
-- --     set_targetdir("$(builddir)/lib")
-- --     set_basename(target_basename)

-- --     local efa_home = os.getenv("EFA_HOME") or "/opt/amazon/efa"
-- --     -- TODO: local abs_home = 

-- --     add_includedirs(
-- --         path.join(efa_home, "/include")
-- --         -- TODO: add abs_home/include
-- --     ) 


-- --     add_files("*.cc")
-- --     remove_files("*_main.cc")
-- --     remove_files("*_test.cc")

-- --     -- -L ${CUDA_HOME}/lib64 -L ${EFA_HOME}/lib -libverbs -lefa -lcudart -lcuda -lpthread  -lgflags -lgtest -lz -lelf
-- --     add_links(path.join(efa_home, "lib"))
-- --     add_links("ibverbs", "efa", "cudart", "z", "elf", "pthread", "gflags", "gtest")
-- --     -- add_links("cudart", "cuda")


-- --     add_defines("USE_CUDA")
-- --     add_rules("cuda")

-- --     if get_config("use_intel_rdma_nic") then 
-- --        add_defines("USE_INTEL_RDMA_NIC=" .. (use_intel_rdma_nic and "1" or "0"))
-- --        add_defines("MTU_4096")
-- --     end

-- --     add_cxxflags(
-- --         "-O3",
-- --         "-g",
-- --         "-std=c++17",
-- --         "-Wno-pointer-arith",
-- --         "-Wno-interference-size",
-- --         "-fPIC",
-- --         "-MMD",
-- --         "-MP"
-- --     )
-- -- -- TODO: add test targets
-- -- -- TODO: add main target