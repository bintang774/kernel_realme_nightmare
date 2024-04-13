#!/usr/bin/bash

# Define common variables
export ARCH=arm64
export SEND_TO_TG=1
export chat_id="-1002131426848"
export token="6373461768:AAFVDAyXGnqVM98nKj1AtpAbFlWkEG1-jqY"
export BUILDER="eraselk"
export BUILD_HOST="github-actions"
export TIMESTAMP=$(date +"%Y%m%d")-$(date +"%H%M%S")
export KBUILD_COMPILER_STRING="$($(pwd)/toolchain/bin/clang -v 2>&1 | awk 'NR==1')"
export PROCS=$(nproc --all)

# Check permission
if [ "$(stat -c %a "$0")" -lt 777 ]; then
    echo "error: Don't have enough permission"
    echo "run 'chmod 0777 $0' and rerun"
    exit 126
fi

# Check dependencies
if ! hash make curl bc zip 2>/dev/null; then
    echo "error: Environment has missing dependencies"
    echo "Install make, curl, bc, and zip!"
    exit 127
fi

# Check anykernel directory
if [ ! -d "./anykernel" ]; then
    echo "error: /anykernel not found!"
    echo "Have you cloned the anykernel?"
    exit 2
fi

send_msg_telegram() {
    local action="$1"
    local message
    case "$action" in
        1) message="Build Started on ${BUILD_HOST}\nBuild status: ${kver}\nBuilder: ${BUILDER}\nDevice: ${DEVICE}\nKernel Version: $(make kernelversion 2>/dev/null | awk 'NR==2')\nDate: $(date)\nZip Name: ${zipn}\nDefconfig: ${DEFCONFIG}\nCompiler: ${KBUILD_COMPILER_STRING}\nBranch: $(git rev-parse --abbrev-ref HEAD)\nLast Commit: $(git log --format='%s' -n 1): $(git log --format='%h' -n 1)" ;;
        2) message="Build failed after ${minutes} minutes and ${seconds} seconds." ;;
        3) message="Build took ${minutes} minutes and ${seconds} seconds.\nSHA512: ${checksum}" ;;
    esac
    curl -s -X POST "https://api.telegram.org/bot$token/sendMessage" \
        -d chat_id="$chat_id" \
        -d "disable_web_page_preview=true" \
        -d "parse_mode=html" \
        -d text="$message" \
        -o /dev/null
}

compile_kernel() {
    rm -f ./out/arch/$ARCH/boot/Image.gz-dtb 2>/dev/null

    export KBUILD_BUILD_USER=$BUILDER
    export KBUILD_BUILD_HOST=$BUILD_HOST
    export PATH="$(pwd)/toolchain/bin:${PATH}"

    make O=out ARCH=$ARCH $DEFCONFIG

    START=$(date +"%s")

    make -j$PROCS O=out \
        ARCH=$ARCH \
        CC=clang \
        AR=llvm-ar \
        NM=llvm-nm \
        AS=llvm-as \
        OBJCOPY=llvm-objcopy \
        OBJDUMP=llvm-objdump \
        STRIP=llvm-strip \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        CONFIG_NO_ERROR_ON_MISMATCH=y \
        CONFIG_DEBUG_SECTION_MISMATCH=y \
        V=0 2>&1 | tee out/build.log

    END=$(date +"%s")
    DIFF=$((END - START))
    minutes=$((DIFF / 60))
    seconds=$((DIFF % 60))
}

zip_kernel() {
    local kernel_image="./out/arch/$ARCH/boot/Image.gz-dtb"
    [ ! -f "$kernel_image" ] && kernel_image="./out/arch/$ARCH/boot/Image.gz"

    cp "$kernel_image" "./anykernel/Image.gz-dtb"
    cd "./anykernel" || exit
    zip -r9 "${zipn}.zip" * -x .git*
    cd ..
    checksum=$(sha512sum "./anykernel/${zipn}.zip" | cut -f1 -d ' ')
    mkdir -p "./out/target"
    mv "./anykernel/${zipn}.zip" "./out/target"
}

build_kernel() {
    clear
    DEFCONFIG="hatsune_defconfig"

    echo "================================="
    echo "Build Started on ${BUILD_HOST}"
    echo "Build status: ${kver}"
    echo "Builder: ${BUILDER}"
    echo "Device: ${DEVICE}"
    echo "Kernel Version: $(make kernelversion 2>/dev/null | awk 'NR==2')"
    echo "Date: $(date)"
    echo "Zip Name: ${zipn}"
    echo "Defconfig: ${DEFCONFIG}"
    echo "Compiler: ${KBUILD_COMPILER_STRING}"
    echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
    echo "Last Commit: $(git log --format='%s' -n 1): $(git log --format='%h' -n 1)"
    echo "================================="

    if [ "$SEND_TO_TG" -eq 1 ]; then
        send_msg_telegram 1
    fi

    compile_kernel

    if [ ! -f "./out/arch/${ARCH}/boot/Image.gz-dtb" ] && [ ! -f "./out/arch/${ARCH}/boot/Image.gz" ]; then
        if [ "$SEND_TO_TG" -eq 1 ]; then
            send_msg_telegram 2
        fi
        echo "================================="
        echo "Build failed after ${minutes} minutes and ${seconds} seconds"
        echo "See build log for troubleshooting."
        echo "================================="
        exit 1
    fi

    zip_kernel

    echo "================================="
    echo "Build took ${minutes} minutes and ${seconds} seconds."
    echo "SHA512: ${checksum}"
    echo "================================="

    if [ "$SEND_TO_TG" -eq 1 ]; then
        send_msg_telegram 3
    fi
}

# Define device-specific variables
export CODENAME="pascal"
export DEVICE="Realme C11, C12, C15 (${CODENAME})"
export zipn="kernel-${CODENAME}-${TIMESTAMP}"

build_kernel
