#! /bin/bash -e

# builds / runs OpenNMS
#
# based on https://github.com/fooker/fooktils/blob/master/opennms-deploy

# Parse arguments
while getopts 'bBxsdoh' OPTFLAG; do
    case "${OPTFLAG}" in
    'b')
        BUILD='yes'
        ;;

    'B')
        BUILD='yes'
        CLEAN='yes'
        ;;

    'x')
        PURGE='yes'
        ;;
    's')
        START='yes'
        ;;
    'd')
        DEBUG='yes'
        ;;
    'o')
        OPEN='yes'
        ;;

    *)
        cat <<- EOF
            Usage: ${0##*/} [options]
            Deploy the opennms build from the current source tree to the system.

                -h      Display this help and exit
                -b      Build the source
                -B      Clean the source before build (implies -b)
                -x      Purge the the database before deployment
                -s      Start opennms
                -d      Start opennms in debug mode
                -o      Open browser
EOF
        exit 254
    esac
done

# Ensure we are running as root
#if [[ "${USER}" != "root" ]]; then
#    exec sudo "${0}" "${@}"
#fi

# Configuration output
[[ "${BUILD}"   == 'yes' ]] && echo -e "\033[0;35m: \033[1;35mBuild the source\033[0m"
[[ "${CLEAN}"   == 'yes' ]] && echo -e "\033[0;35m: \033[1;35mClean the source before build\033[0m"
[[ "${PURGE}"   == 'yes' ]] && echo -e "\033[0;35m: \033[1;35mPurge database before installation\033[0m"
[[ "${START}"   == 'yes' ]] && echo -e "\033[0;35m: \033[1;35mStart OpenNMS\033[0m"
[[ "${DEBUG}"   == 'yes' ]] && echo -e "\033[0;35m: \033[1;35mStart OpenNMS in debug mode\033[0m"

# Define the target
TARGET=/opt/opennms

if [[ "$START" == 'yes' || "$DEBUG" == 'yes' ]]; then
    # Try to stop existing target if not empty
    if [[ -x "${TARGET}/bin/opennms" && -f "${TARGET}/etc/configured" ]]; then
        echo -e "\033[0;37m==> \033[1;37mStop existing OpenNMS instance\033[0m"
        sudo ${TARGET}/bin/opennms -v stop
    fi

    # Clean existing deployment
    echo -e "\033[0;37m==> \033[1;37mClean existing deployment\033[0m"
    sudo find "${TARGET}" \
        -depth \
        -mindepth 1 \
        -delete
fi

# Clean the source tree
if [[ "${CLEAN}" == 'yes' ]]; then
    echo -e "\033[0;37m==> \033[1;37mClean the source\033[0m"
    ./clean.pl
fi

# Build the source tree
if [[ "${BUILD}" == 'yes' ]]; then
    echo -e "\033[0;37m==> \033[1;37mBuild the source\033[0m"
    ./compile.pl -DskipTests -DskipITs
    ./assemble.pl -DskipTests -DskipITs -Dopennms.home=/opt/opennms -pdir
fi

# Purge the database
if [[ "${PURGE}" == 'yes' ]]; then
    echo -e "\033[0;37m==> \033[1;37mPurge the database\033[0m"
    dropdb --if-exists opennms
fi

# Check if we have a valid source
SOURCE=$(find . \
    -maxdepth 2 \
    -type d \
    -path "./target/opennms-*")
if [[ -z "${SOURCE}" ]] || [[ $(wc -l <<< "${SOURCE}") -ne 1 ]]; then
    echo -e "\033[0;31mNo valid opennms target found\033[0m" >&2
    exit 1
fi

# Make the source path absolute
SOURCE="$(realpath "${SOURCE}")"

if [[ "$DEBUG" == 'yes' || "$START" == 'yes' ]]; then

    # Copy and link directories
    echo -e "\033[0;37m==> \033[1;37mCopy build to target\033[0m"
    cp --recursive --reflink=auto -t "${TARGET}" "${SOURCE}/etc"
    cp --recursive --reflink=auto -t "${TARGET}" "${SOURCE}/data"
    cp --recursive --reflink=auto -t "${TARGET}" "${SOURCE}/share"
    cp --recursive --reflink=auto -t "${TARGET}" "${SOURCE}/logs"

    ln --symbolic -t "${TARGET}" "${SOURCE}/bin"
    ln --symbolic -t "${TARGET}" "${SOURCE}/contrib"
    ln --symbolic -t "${TARGET}" "${SOURCE}/docs"
    ln --symbolic -t "${TARGET}" "${SOURCE}/jetty-webapps"
    ln --symbolic -t "${TARGET}" "${SOURCE}/lib"
    ln --symbolic -t "${TARGET}" "${SOURCE}/deploy"
    ln --symbolic -t "${TARGET}" "${SOURCE}/system"

    # Copy configuration
    if [ -d "${TARGET}.template" ]; then
        echo -e "\033[0;37m==> \033[1;37mCopy configuration template to target\033[0m"
        rsync --recursive "${TARGET}.template/" "${TARGET}"
    fi
fi

# Create database
if [[ "${PURGE}" == 'yes' ]]; then
    echo -e "\033[0;37m==> \033[1;37mCreate database\033[0m"
    createdb -O opennms opennms
fi

if [[ "$DEBUG" == 'yes' || "$START" == 'yes' ]]; then

    # Configure java
    echo -e "\033[0;37m==> \033[1;37mConfigure Java version\033[0m"
    sudo ${TARGET}/bin/runjava \
        -s

    # Run installation / update
    echo -e "\033[0;37m==> \033[1;37mConfigure OpenNMS instance\033[0m"
    sudo ${TARGET}/bin/install \
        -d \
        -i \
        -s \
        -l "$(realpath "$(dirname "${0}")/jicmp/.libs"):$(realpath "$(dirname "${0}")/jicmp6/.libs"):$(realpath "$(dirname "${0}")/jrrd2/dist")"
fi

# Start target
if [[ "${DEBUG}" == 'yes' ]]; then
    echo -e "\033[0;37m==> \033[1;37mStart OpenNMS instance in debug mode\033[0m"
    sudo ${TARGET}/bin/opennms -v -t start
elif [[ "$START" == 'yes' ]]; then
    echo -e "\033[0;37m==> \033[1;37mStart OpenNMS instance\033[0m"
    sudo ${TARGET}/bin/opennms -v start
fi

if [[ "$DEBUG" == 'yes' || "$START" == 'yes' ]]; then
    # Wait for OSGi manhole to bekome available and enable module reloading
    while ! nc -z localhost 8101; do echo -n '.'; sleep 0.1; done
    sshpass -p admin \
    ssh \
        -l admin \
        -p 8101 \
        -o "StrictHostKeyChecking no" \
        -o "NoHostAuthenticationForLocalhost yes" \
        -o "HostKeyAlgorithms +ssh-dss" \
        localhost \
    bundle:watch '*'
fi

# Open browser window
if [[ "${OPEN}" == 'yes' ]]; then
    echo -e "\033[0;37m==> \033[1;37mOpen browser\033[0m"
    xdg-open "http://localhost:8980/opennms" &
fi

