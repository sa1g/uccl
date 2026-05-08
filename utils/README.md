It happens that a system doesn't have Python installed and/or the default c compiler is not gcc/clang
so xmake's python module compilation fails (e.g. with nvc++). In that case perform `xmake -v` here,
without any loaded module. Check which compiler is being used, it shouldn't be one like `nvc++` or `nvc`.