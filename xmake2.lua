option("tests", {default = false, description = "Enable Tests"})

print("Tests: " .. tostring(get_config("tests")))

-- target("foo")
--     set_kind("binary")
--     add_files("src/*.cpp")
--     if has_config("tests") then
--         add_defines("TESTS")
--     end