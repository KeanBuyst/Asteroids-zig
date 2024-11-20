# Asteroids in Zig

Simple asteroids arcade game made using zig
and raylib-zig.

Controls
* `A` - rotate left
* `W` - move forward
* `D` - rotate right
* `SPACE` - shoot

## Build

Requires Zig `0.13.0`


```
git clone https://github.com/KeanBuyst/Asteroids-zig.git --recursive
cd ./Asteroids-zig
zig build run
```
The submodule `raylib-zig` might be for a later version of zig
depending at which time you are trying to build this. Therefore
you might have to replace the raylib-zig folder with an older
version, or update the `build.zig` file. (Potentially also other src files)
