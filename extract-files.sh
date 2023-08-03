#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017-2020 The LineageOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -e

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}"/../../..

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at $HELPER"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

ONLY_COMMON=
ONLY_TARGET=
SECTION=
KANG=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --only-common )
                ONLY_COMMON=true
                ;;
        --only-target )
                ONLY_TARGET=true
                ;;
        -n | --no-cleanup )
            CLEAN_VENDOR=false
            ;;
        -k | --kang )
                KANG="--kang"
                ;;
        -s | --section )
                SECTION="${2}"; shift
                CLEAN_VENDOR=false
                ;;
        * )
                SRC="${1}"
                ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup() {
    case "${1}" in

    system_ext/lib64/libdpmframework.so)
        sed -i "s/libhidltransport.so/libcutils-v29.so\x00\x00\x00/" "${2}"
        ;;

    # Patch libmmcamera2_stats_modules
    vendor/lib/libmmcamera2_stats_modules.so)
        sed -i "s|/data/misc/camera|/data/vendor/qcam|g" "${2}"
        "${PATCHELF}" --remove-needed libandroid.so "${2}"
        "${PATCHELF}" --remove-needed libgui.so "${2}"
        ;;

    # Patch blobs for VNDK
    vendor/lib/libmmcamera_ppeiscore.so)
        "${PATCHELF}" --remove-needed libgui.so "${2}"
        ;;
    vendor/lib/libmpbase.so)
        "${PATCHELF}" --remove-needed libandroid.so "${2}"
        ;;

    # Hex edit /firmware/image to /vendor/firmware_mnt to delete the outdated rootdir symlinks
    vendor/lib64/hw/fingerprint.qcom.so)
        sed -i "s|/firmware/image|/vendor/f/image|g" "${2}"
        ;;

    # Hex edit libaudcal.so to store acdbdata in new paths
    vendor/lib/libaudcal.so | vendor/lib64/libaudcal.so)
        sed -i "s|/data/vendor/misc/audio/acdbdata/delta/|/data/vendor/audio/acdbdata/delta/\x00\x00\x00\x00\x00|g" "${2}"
        ;;

    # Hex edit camera blobs to use /data/vendor/qcam
   vendor/lib/libmm-qcamera.so | vendor/lib/libmmcamera2_cpp_module.so | vendor/lib/libmmcamera2_iface_modules.so | vendor/lib/libmmcamera2_imglib_modules.so | vendor/lib/libmmcamera2_mct.so | vendor/lib/libmmcamera2_pproc_modules.so | vendor/lib/libmmcamera2_stats_algorithm.so | vendor/lib/libmmcamera_dbg.so | vendor/lib/libmmcamera_hvx_grid_sum.so | vendor/lib/libmmcamera_hvx_zzHDR.so | vendor/lib/libmmcamera_imglib.so | vendor/lib/libmmcamera_isp_mesh_rolloff44.so | vendor/lib/libmmcamera_pdaf.so | vendor/lib/libmmcamera_pdafcamif.so | vendor/lib/libmmcamera_tintless_algo.so | vendor/lib/libmmcamera_tintless_bg_pca_algo.so | vendor/lib/libmmcamera_tuning.so)
        sed -i "s|/data/misc/camera|/data/vendor/qcam|g" "${2}"
        ;;
    vendor/bin/mm-qcamera-daemon)
        sed -i "s|/data/vendor/camera/cam_socket%d|/data/vendor/qcam/camer_socket%d|g" "${2}"
        ;;

	# Remove libmedia.so dependency from lib-dplmedia.so
    vendor/lib64/lib-dplmedia.so)
        "${PATCHELF}" --remove-needed libmedia.so "${2}"
        ;;

    vendor/etc/permissions/qti_libpermissions.xml)
        sed -i 's|"android.hidl.manager-V1.0-java"|"android.hidl.manager@1.0-java"|' ${2}
        ;;

        system_ext/etc/init/dpmd.rc)
        sed -i "s/\/system\/product\/bin\//\/system\/system_ext\/bin\//g" "${2}"
        ;;

    system_ext/etc/permissions/com.qti.dpmframework.xml | system_ext/etc/permissions/dpmapi.xml)
        sed -i "s/\/system\/product\/framework\//\/system\/system_ext\/framework\//g" "${2}"
        ;;

    system_ext/etc/permissions/qcrilhook.xml | system_ext/etc/permissions/telephonyservice.xml)
        sed -i "s/\/system\/framework\//\/system\/system_ext\/framework\//g" "${2}"
        ;;

    system_ext/etc/permissions/qti_libpermissions.xml)
        sed -i "s/name=\"android.hidl.manager-V1.0-java/name=\"android.hidl.manager@1.0-java/g" "${2}"
        ;;

    # Rename vulkan.msm8953
    vendor/lib/hw/vulkan.msm8996.so | vendor/lib64/hw/vulkan.msm8996.so)
        "${PATCHELF}" --set-soname "vulkan.msm8996.so" "${2}"
        ;;
    esac
}

if [ -z "${ONLY_TARGET}" ]; then
    # Initialize the helper for common device
    setup_vendor "${DEVICE_COMMON}" "${VENDOR}" "${ANDROID_ROOT}" true "${CLEAN_VENDOR}"

    extract "${MY_DIR}/proprietary-files.txt" "${SRC}" \
            "${KANG}" --section "${SECTION}"
fi

if [ -z "${ONLY_COMMON}" ] && [ -s "${MY_DIR}/../${DEVICE}/proprietary-files.txt" ]; then
    # Reinitialize the helper for device
    source "${MY_DIR}/../${DEVICE}/extract-files.sh"
    setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

    extract "${MY_DIR}/../${DEVICE}/proprietary-files.txt" "${SRC}" \
            "${KANG}" --section "${SECTION}"
fi

"${MY_DIR}/setup-makefiles.sh"
