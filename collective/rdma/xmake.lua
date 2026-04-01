rule("ccl.rdma")
    on_config(function (target)
        target:add("cxxflags", "-Wno-pointer-arith", "-Wno-interference-size", "-fPIC", "-MMD")
    end)
rule_end()

target("ccl_rdma_core")
    set_kind("static")
    set_targetdir("$(builddir)/lib")

    add_rules("uccl.common", "uccl.backend", "ccl.rdma")

    add_files("*.cc")
    remove_files("*_main.cc", "*_test.cc", "*_plugin.cc")

-- Plugin
target("ccl_rdma_plugin")
    set_kind("shared")
    set_targetdir("$(builddir)/lib")

    add_rules("uccl.common", "uccl.backend", "ccl.rdma")
    add_deps("ccl_rdma_core")

    add_files("*_plugin.cc")

    set_basename(get_config("backend") == "cuda" and "nccl-net-uccl" or "rccl-net-uccl")

-- ====================================================================
-- Tests & Benchmarks
-- ====================================================================

for _, test_file in ipairs(os.files("*_test.cc")) do
    local test_name = test_file:match("([^/]+)_test%.cc$")    
    target("test_collective_rdma_" .. test_name)
        set_kind("binary")
        set_symbols("debug")
        
        set_targetdir("$(builddir)/test")
        add_files(test_file)

        add_deps("ccl_rdma_core")
        add_packages("gtest", "gflags")

end
