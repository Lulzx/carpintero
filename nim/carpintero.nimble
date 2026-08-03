version       = "0.1.0"
author        = "Carpintero"
description   = "Compiled matcher core for the Carpintero grammar dialect"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.0.0"

task test, "run the matcher tests":
    exec "nim c --hints:off -r tests/test_vm.nim"
