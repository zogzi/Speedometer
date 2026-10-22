"""Run the Lua specs using the system Lua 5.4 shared library; no pip packages."""
import ctypes
import ctypes.util
import os
from pathlib import Path


def main():
    os.chdir(Path(__file__).resolve().parents[1])
    library = ctypes.util.find_library("lua5.4")
    if not library:
        raise SystemExit("Install Lua 5.4 and run: lua5.4 tests/client_spec.lua")
    lua = ctypes.CDLL(library)
    pointer = ctypes.c_void_p
    lua.luaL_newstate.restype = pointer
    lua.luaL_openlibs.argtypes = [pointer]
    lua.luaL_loadfilex.argtypes = [pointer, ctypes.c_char_p, ctypes.c_char_p]
    lua.luaL_loadfilex.restype = ctypes.c_int
    lua.lua_pcallk.argtypes = [pointer, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ssize_t, pointer]
    lua.lua_pcallk.restype = ctypes.c_int
    lua.lua_tolstring.argtypes = [pointer, ctypes.c_int, pointer]
    lua.lua_tolstring.restype = ctypes.c_char_p
    lua.lua_close.argtypes = [pointer]
    state = lua.luaL_newstate()
    if not state:
        raise SystemExit("Unable to allocate Lua state")
    try:
        lua.luaL_openlibs(state)
        status = lua.luaL_loadfilex(state, b"tests/client_spec.lua", None)
        if not status:
            status = lua.lua_pcallk(state, 0, 0, 0, 0, None)
        if status:
            raise SystemExit(lua.lua_tolstring(state, -1, None).decode())
    finally:
        lua.lua_close(state)


if __name__ == "__main__":
    main()
