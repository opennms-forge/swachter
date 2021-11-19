#! /bin/bash -e

# builds / runs OpenNMS
#
# based on https://github.com/fooker/fooktils/blob/master/opennms-deploy

SUSPEND='no'

# Parse arguments
while getopts 'abBqxsdDorh' OPTFLAG; do
    case "${OPTFLAG}" in
    'a')
        ASSEMBLE='yes'
        ;;
    'b')
        BUILD='yes'
        ASSEMBLE='yes'
        ;;

    'B')
        BUILD='yes'
        ASSEMBLE='yes'
        CLEAN='yes'
        ;;

    'r')
        RESOLVE='yes'
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
    'D')
        DEBUG='yes'
        SUSPEND='yes'
        ;;
    'o')
        OPEN='yes'
        ;;
    'q')
        STOP='yes'
        ;;

    *)
        cat <<- EOF
            Usage: ${0##*/} [options]
            Deploy the opennms build from the current source tree to the system.

                -h      Display this help and exit
                -r      Resolve dependencies
                -a      Assemble the build
                -b      Build the source (implies -a)
                -B      Clean the source before build (implies -ab)
                -x      Purge the the database before deployment
                -s      Start opennms
                -d      Start opennms in debug mode
                -D      Start opennms in debug mode and suspend until debugger is attached
                -o      Open browser
                -q      Stop opennms
EOF
        exit 254
    esac
done

# Configuration output
[[ "${BUILD}"   == 'yes' ]] && echo -e "\033[0;35m: \033[1;35mBuild the source\033[0m"
[[ "${CLEAN}"   == 'yes' ]] && echo -e "\033[0;35m: \033[1;35mClean the source before build\033[0m"
[[ "${PURGE}"   == 'yes' ]] && echo -e "\033[0;35m: \033[1;35mPurge database before installation\033[0m"
[[ "${START}"   == 'yes' ]] && echo -e "\033[0;35m: \033[1;35mStart OpenNMS\033[0m"
[[ "${DEBUG}"   == 'yes' ]] && echo -e "\033[0;35m: \033[1;35mStart OpenNMS in debug mode\033[0m"
[[ "${STOP}"    == 'yes' ]] && echo -e "\033[0;35m: \033[1;35mStop OpenNMS\033[0m"

# Define the target
TARGET=/opt/opennms

if [[ "$RESOLVE" == 'yes' ]]; then
  mvn dependency:resolve
fi

if [[ "$START" == 'yes' || "$DEBUG" == 'yes' || "$STOP" == 'yes' ]]; then
    # Try to stop existing target if not empty
    if [[ -x "${TARGET}/bin/opennms" && -f "${TARGET}/etc/configured" ]]; then
        echo -e "\033[0;37m==> \033[1;37mStop existing OpenNMS instance\033[0m"
        ${TARGET}/bin/opennms -v stop
    fi

    # Clean existing deployment
    echo -e "\033[0;37m==> \033[1;37mClean existing deployment\033[0m"
    find "${TARGET}" \
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
    # ensure that the target folder is deleted
    # -> when OpenNms versions are changed (by changing the branch) this results in different target artifacts
    # -> later on this script would not know which one to start
    rm -rf target
    ./compile.pl -DskipTests -DskipITs
fi

# Build the source tree
if [[ "${ASSEMBLE}" == 'yes' ]]; then
    echo -e "\033[0;37m==> \033[1;37mAssemble\033[0m"
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
    ${TARGET}/bin/runjava \
        -s

    # Run installation / update
    echo -e "\033[0;37m==> \033[1;37mConfigure OpenNMS instance\033[0m"
    ${TARGET}/bin/install \
        -d \
        -i \
        -s \
        -l "$(realpath "$(dirname "${0}")/jicmp/.libs"):$(realpath "$(dirname "${0}")/jicmp6/.libs"):$(realpath "$(dirname "${0}")/jrrd2/dist")"
fi

# Start target
if [[ "${DEBUG}" == 'yes' ]]; then
    tSwitch=t
    if [[ "${SUSPEND}" == 'yes' ]]; then
      tSwitch=T
    fi
    echo -e "\033[0;37m==> \033[1;37mStart OpenNMS instance in debug mode\033[0m"
    ${TARGET}/bin/opennms -v -$tSwitch start
elif [[ "$START" == 'yes' ]]; then
    echo -e "\033[0;37m==> \033[1;37mStart OpenNMS instance\033[0m"
    ${TARGET}/bin/opennms -v start
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
