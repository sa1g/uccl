-- include/xmake.lua
target("util")
    set_kind("headeronly")
    add_headerfiles("util/*.h")
    add_includedirs(".", {public = true})
target_end()