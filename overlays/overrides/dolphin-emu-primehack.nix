# Fix dolphin-emu-primehack CMake compatibility issues
# Uses STABLE because unstable has mbedtls library conflicts
{
  stable,
  ...
}:
{
  dolphin-emu-primehack = stable.dolphin-emu-primehack.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      # Fix CMake minimum version in all vendored dependencies
      echo "Fixing CMake minimum versions in vendored dependencies..."

      find Externals -name "CMakeLists.txt" | while read file; do
        if grep -qi "cmake_minimum_required" "$file"; then
          echo "Patching: $file"
          cp "$file" "$file.tmp"

          # Replace cmake_minimum_required with version < 3.5
          sed -i -E 's/cmake_minimum_required\s*\(\s*VERSION\s+[0-2](\.[0-9]+)*([^)]*)\)/cmake_minimum_required(VERSION 3.5)/gi' "$file.tmp"
          sed -i -E 's/cmake_minimum_required\s*\(\s*VERSION\s+3\.[0-4](\.[0-9]+)*([^)]*)\)/cmake_minimum_required(VERSION 3.5)/gi' "$file.tmp"

          mv "$file.tmp" "$file"
          grep -i "cmake_minimum_required" "$file" | head -1
        fi
      done
    '';
  });
}
