script_folder="/Users/paul/Projects/arkavo/app/opentdf-client/build/Debug/generators"
echo "echo Restoring environment" > "$script_folder/deactivate_conanrunenv-debug-armv8.sh"
for v in OPENSSL_MODULES
do
    is_defined="true"
    value=$(printenv $v) || is_defined="" || true
    if [ -n "$value" ] || [ -n "$is_defined" ]
    then
        echo export "$v='$value'" >> "$script_folder/deactivate_conanrunenv-debug-armv8.sh"
    else
        echo unset $v >> "$script_folder/deactivate_conanrunenv-debug-armv8.sh"
    fi
done


export OPENSSL_MODULES="/Users/paul/.conan2/p/b/opens7c84ec0a73cfc/p/lib/ossl-modules"