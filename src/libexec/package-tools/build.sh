#! /bin/bash

if [[ $# != 1 ]]; then
    echo "Usage: ${0##*/} {secret_key}"
    exit 1
fi

set -x

# Get azk root path
abs_dir() {
  cd "${1%/*}"; link=`readlink ${1##*/}`;
  if [ -z "$link" ]; then pwd; else abs_dir $link; fi
}

export AZK_ROOT_PATH=`cd \`abs_dir ${BASH_SOURCE:-$0}\`/../../..; pwd`
export AZK_BUILD_TOOLS_PATH=${AZK_ROOT_PATH}/src/libexec/package-tools

export PATH=${AZK_ROOT_PATH}/bin:$PATH
SECRET_KEY=$1

# Go to azk path
cd $AZK_ROOT_PATH

source .dependencies

quiet() {
    $@ > /dev/null 2>&1
}

setup() {
    quiet rm -Rf azk-agent-start.log package
    make clean && make
    make
}

tear_down() {
    azk agent stop > /dev/null 2>&1
    rm azk-agent-start.log
}

step() { echo $@ | sed -e :a -e 's/^.\{1,72\}$/&./;ta';}

step_done() {
    if [[ $# > 0 ]] && [[ $1 != 0 ]]; then
        echo "[ FAIL ]"
        if [[ $# == 2 ]] && [[ "$2" == "--exit" ]]; then
            exit $1
        fi
    else
        echo "[ DONE ]"
    fi
}

step_fail() { echo "[ FAIL ]"; }

start_agent() {
    quiet azk agent stop
    sleep 3
    AZK_VM_MEMORY=3072 azk agent start
}

generate_packages(){
    mkdir -p package/deb && wget "https://github.com/azukiapp/libnss-resolver/releases/download/v${LIBNSS_RESOLVER_VERSION}/ubuntu12-libnss-resolver_${LIBNSS_RESOLVER_VERSION}_amd64.deb" -O "package/deb/precise-libnss-resolver_${LIBNSS_RESOLVER_VERSION}_amd64.deb" && wget "https://github.com/azukiapp/libnss-resolver/releases/download/v${LIBNSS_RESOLVER_VERSION}/ubuntu14-libnss-resolver_${LIBNSS_RESOLVER_VERSION}_amd64.deb" -O "package/deb/trusty-libnss-resolver_${LIBNSS_RESOLVER_VERSION}_amd64.deb"
    mkdir -p package/rpm && wget "https://github.com/azukiapp/libnss-resolver/releases/download/v${LIBNSS_RESOLVER_VERSION}/fedora20-libnss-resolver-${LIBNSS_RESOLVER_VERSION}-1.x86_64.rpm" -O "package/rpm/fedora20-libnss-resolver-${LIBNSS_RESOLVER_VERSION}-1.x86_64.rpm"

    step "Creating deb package"
    make package_deb
    step_done $?

    step "Creating rpm package"
    make package_rpm LINUX_CLEAN=
    step_done $?

    step "Creating mac package"
    make package_mac
    step_done $?

    step "Creating tar file"
    rm -Rf package.tar.gz
    tar -zcf package.tar.gz package/
    step_done $?
}

step "Setup"
setup
step_done $? --exit

step "Starting agent"
start_agent
step_done $? --exit

generate_packages

azk shell package -c "rm -Rf /azk/aptly/*"

step "Creating Ubuntu 12.04 repository"
azk shell package -c "src/libexec/package-tools/ubuntu/generate.sh ${LIBNSS_RESOLVER_VERSION} precise ${SECRET_KEY}"
${AZK_BUILD_TOOLS_PATH}/ubuntu/test.sh precise
step_done $?

step "Creating Ubuntu 14.04 repository"
azk shell package -c "src/libexec/package-tools/ubuntu/generate.sh ${LIBNSS_RESOLVER_VERSION} trusty ${SECRET_KEY}"
${AZK_BUILD_TOOLS_PATH}/ubuntu/test.sh trusty
step_done $?

step "Creating Fedora 20 repository"
azk shell package -c "src/libexec/package-tools/fedora/generate.sh fedora20 ${SECRET_KEY}"
${AZK_BUILD_TOOLS_PATH}/fedora/test.sh fedora20
step_done $?

step "Creating Mac repository"
${AZK_BUILD_TOOLS_PATH}/mac/generate.sh
${AZK_BUILD_TOOLS_PATH}/mac/test.sh
step_done $?

tear_down