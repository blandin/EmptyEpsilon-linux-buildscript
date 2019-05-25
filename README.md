# EmptyEpsilon-linux-buildscript
The purpose of this Bash script is to facilitate and expedite the process of building [EmptyEpsilon](https://daid.github.io/EmptyEpsilon/) on Linux platforms. It handles everything: from installing/updating the build environment, to checking out the source code, to compiling and installing the game.

## Current limitations
- Only verified working on certain distributions
  - Ubuntu 16.04 and higher
  - Peppermint 8 and higher
  - Debian 9 and higher
  - The compatibility check can be bypassed, but currently the script is hard coded to make use of the dpkg package management system.
