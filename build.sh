#!/usr/bin/bash

# Define some things
# Kernel common
export ARCH=arm64
# Telegram API
export SEND_TO_TG=1
export chat_id="-1002131426848"
export token="6373461768:AAFVDAyXGnqVM98nKj1AtpAbFlWkEG1-jqY"
# Telegram && Output
export kver="debug"
export CODENAME="pascal"
export DEVICE="Realme C11, C12, C15 (${CODENAME})"
export BUILDER="eraselk"
export BUILD_HOST="github-actions"
export TIMESTAMP=$(date +"%Y%m%d")-$(date +"%H%M%S")
export KBUILD_COMPILER_STRING="$(./toolchain/bin/clang -v 2>&1 | head -n 1)"
export FW="RUI1"
export zipn="kernel-${CODENAME}-${FW}-${TIMESTAMP}"

# Needed by script
PROCS="$(nproc --all)"

# Check permission
script_permissions=$(stat -c %a "$0")
if [ "$script_permissions" -lt 777 ]; then
    echo -e "error: Don't have enough permission"
    echo "run 'chmod 0777 origami_kernel_builder.sh' and rerun"
    exit 126
fi

# Check dependencies
if ! hash make curl bc zip 2>/dev/null; then
        echo -e "error: Environment has missing dependencies"
        echo "Install make, curl, bc, and zip !"
        exit 127
fi

if [ ! -d "${PWD}/anykernel" ]; then
    echo -e "error: /anykernel not found!"
    echo "have you clone the anykernel?"
    exit 2
fi

send_msg_telegram() {
    case "$1" in
    1) curl -s -X POST "https://api.telegram.org/bot$token/sendMessage" \
                -d chat_id="$chat_id" \
                -d "disable_web_page_preview=true" \
                -d "parse_mode=html" \
                -d text="<b>~~~ eraselk's CI ~~~</b>
<b>Build Started on ${BUILD_HOST}</b>
<b>Build status</b>: <code>${kver}</code>
<b>Builder</b>: <code>${BUILDER}</code>
<b>Device</b>: <code>${DEVICE}</code>
<b>Kernel Version</b>: <code>$(make kernelversion 2>/dev/null | awk 'NR==2')</code>
<b>Date</b>: <code>$(date)</code>
<b>Zip Name</b>: <code>${zipn}</code>
<b>Defconfig</b>: <code>${DEFCONFIG}</code>
<b>Compiler</b>: <code>${KBUILD_COMPILER_STRING}</code>
<b>Branch</b>: <code>$(git rev-parse --abbrev-ref HEAD)</code>
<b>Last Commit</b>: <code>$(git log --format="%s" -n 1): $(git log --format="%h" -n 1)</code>" \
                -o /dev/null
        ;;
    2) curl -s -F document=@./out/build.log "https://api.telegram.org/bot$token/sendDocument" \
                -F chat_id="$chat_id" \
                -F "disable_web_page_preview=true" \
                -F "parse_mode=html" \
                -F caption="Build failed after ${minutes} minutes and ${seconds} seconds." \
                -o /dev/null \
                -w "" >/dev/null 2>&1
        ;;
    3) curl -s -F document=@./out/target/"${zipn}".zip "https://api.telegram.org/bot$token/sendDocument" \
                -F chat_id="$chat_id" \
                -F "disable_web_page_preview=true" \
                -F "parse_mode=html" \
                -F caption="Build took ${minutes} minutes and ${seconds} seconds.
<b>SHA512</b>: <code>${checksum}</code>" \
                -o /dev/null \
                -w "" >/dev/null 2>&1

        curl -s -F document=@./out/build.log "https://api.telegram.org/bot$token/sendDocument" \
                -F chat_id="$chat_id" \
                -F "disable_web_page_preview=true" \
                -F "parse_mode=html" \
                -F caption="Build log" \
                -o /dev/null \
                -w "" >/dev/null 2>&1
        ;;
    esac
}

compile_kernel() {
    rm ./out/arch/${ARCH}/boot/Image.gz-dtb 2>/dev/null

    export KBUILD_BUILD_USER=${BUILDER}
    export KBUILD_BUILD_HOST=${BUILD_HOST}
    export KBUILD_COMPILER_STRING="gacorprjkt"
    export PATH="$(pwd)/toolchain/bin:${PATH}"

    make O=out ARCH=${ARCH} ${DEFCONFIG}
    START=$(date +"%s")
    
    make -j"$PROCS" O=out \
    ARCH=${ARCH} \
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
    export minutes=$((DIFF / 60))
    export seconds=$((DIFF % 60))
}

zip_kernel() {
    # Move kernel image to anykernel zip
if [ ! -f "./out/arch/${ARCH}/boot/Image.gz-dtb" ]; then
    cp ./out/arch/${ARCH}/boot/Image.gz ./anykernel
else
    cp ./out/arch/${ARCH}/boot/Image.gz-dtb ./anykernel
fi
    # Zip the kernel
    cd ./anykernel
    zip -r9 "${zipn}".zip * -x .git*
    cd ..

    # Generate checksum of kernel zip
    export checksum=$(sha512sum ./anykernel/"${zipn}".zip | cut -f1 -d ' ')

    if [ ! -d "./out/target" ]; then
        mkdir ./out/target
    fi

if [ ! -f "./out/arch/${ARCH}/boot/Image.gz-dtb" ]; then
    rm -f ./anykernel/Image.gz
else
    rm -f ./anykernel/Image.gz-dtb
fi

    # Move the kernel zip to ./out/target
    mv ./anykernel/${zipn}.zip ./out/target
}

build_kernel() {
clear
    export DEFCONFIG="hatsune_defconfig"

    echo -e "================================="
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
    echo "Last Commit: $(git log --format="%s" -n 1): $(git log --format="%h" -n 1)"
    echo -e "================================="

    if [ "$SEND_TO_TG" -eq 1 ]; then
        send_msg_telegram 1
    fi

    compile_kernel

    if [ ! -f "./out/arch/${ARCH}/boot/Image.gz-dtb" ] && [ ! -f "./out/arch/${ARCH}/boot/Image.gz" ]; then
        if [ "$SEND_TO_TG" -eq 1 ]; then
            send_msg_telegram 2
        fi
        echo -e "================================="
        echo -e "Build failed after ${minutes} minutes and ${seconds} seconds"
        echo "See build log for troubleshooting."
        echo -e "================================="
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

build_kernel
