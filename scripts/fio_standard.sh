#!/bin/bash

# 
# help
if [ "$#" -lt 7 ] || [[ "$1" == "-h" || "$1" == "help" || "$1" == "--help" ]]; then
    echo "Usage: $0 filename rw_mode size qd numjobs bs disk_model output_format <runtime>"
    echo "Usage: $0 -h/--help/help"
    exit 1
fi

fio_version=$(fio -v)

# default，runtime 3000
runtime=3000 

ramp_time="0"
FIO_CMD="fio"

# fio parameter
filename=$1
if [[ "$2" =~ ^(rw|randrw)([0-9]{1,2}|100)$ ]]; then     
    rw_mode="${BASH_REMATCH[1]}"  
    rwmixread="${BASH_REMATCH[2]}"
    FIO_CMD+=" --rwmixread=$rwmixread " 
elif [[ "$2" == "rw" ]]; then
    rw_mode="randwrite"
elif [[ "$2" == "sw" ]]; then
    rw_mode="write"
elif [[ "$2" == "rr" ]]; then
    rw_mode="randread"
elif [[ "$2" == "sr" ]]; then
    rw_mode="read"
else
    rw_mode=$2
fi
size=$3
qd=$4
numjobs=$5
bs=$6
disk_model=$7
output_format=$8

if [ "$#" -eq 9 ] ; then
    if [ "$9" != "3000" ]; then
    #if [[ "$3" =~ ^[0-9]{1,2}%$ ]] && [ "${3%?}" -le 100 ] ; then
        runtime=$9
        FIO_CMD+=" --time_based=1 " 
    fi
fi

ALIGN=$bs
dev_name=$(basename "$filename")
rotational_path="/sys/block/$dev_name/queue/rotational"
if [[ -f "$rotational_path" ]]; then
    rotational=$(cat "$rotational_path")
    #echo "Device $dev_name rotational = $rotational"
    if [[ "$rotational" -eq 1 ]]; then
        STRIP_SIZE="256K"
        strip_num=${STRIP_SIZE%K}
        if [[ "$disk_model" =~ ^([0-9]+)R([0-9])J ]]; then
            n="${BASH_REMATCH[1]}"
            t="${BASH_REMATCH[2]}"

            case "$t" in
                0)
                    result=$((n * strip_num))
                    ;;
                5)
                    result=$(((n - 1) * strip_num))
                    ;;
                6)
                    result=$(((n - 2) * strip_num))
                    ;;
                x)
                    echo "JBOD,对齐参数设置为:$ALIGN"
                    ;;
                *)
                    echo "HDD的其他raid级别,对齐参数设置为: $ALIGN"
                    ;;
            esac
            ALIGN="${result}K"
            echo "HDD: $ALIGN"
        else
            echo "请检查disk_model, 未知RAID级别和成员盘数,对齐参数设置为: $ALIGN"
        fi
        
    elif [[ "$rotational" -eq 0 ]]; then
        #echo "$dev_name is SSD"
        STRIP_SIZE="64K"
        strip_num=${STRIP_SIZE%K}
        if [[ "$disk_model" =~ ^([0-9]+)R([0-9])J ]]; then
            n="${BASH_REMATCH[1]}"
            t="${BASH_REMATCH[2]}"

            case "$t" in
                0)
                    result=$((n * strip_num))
                    ;;
                5)
                    result=$(((n - 1) * strip_num))
                    ;;
                6)
                    result=$(((n - 2) * strip_num))
                    ;;
                x)
                    echo "JBOD,对齐参数设置为: $ALIGN"
                    ;;
                *)
                    echo "SSD的其他raid级别,对齐参数设置为: $ALIGN"
                    ;;
            esac
            ALIGN="${result}K"
        else
            echo "请检查disk_model, 未知RAID级别和成员盘数,对齐参数设置为: $ALIGN"
        fi
    else
        echo "Unknown rotational value for $dev_name: $rotational"
    fi
else
    echo "Cannot find rotational info for $dev_name"
fi


if [[ "$rw_mode" == rand* ]]; then
    FIO_CMD+=" --blockalign=$ALIGN "
fi

# check parameter
#check filename
if [[ "$1" =~ ^/dev/sd[a-z]{1,2}$ ]]; then    
    if ! lsblk | grep -q "$(basename "$1")"; then         
    echo "error: device $1 do not exist" 
    echo "error: $1, Please set valid filename-device!"
    echo "Usage: $0 filename rw_mode size qd numjobs bs disk_model output_format <runtime>"          
    exit 1     
    fi 
elif [ -d "$1" ]; then
    echo ""   
else
    if [ ! -e "$1" ]; then       
        echo "error: path $1 do not exist"
        echo "error: $1, Please set valid filename-path!"
        echo "Usage: $0 filename rw_mode size qd numjobs bs disk_model output_format <runtime>"           
        exit 1     
    fi
fi
# check rw_mode
if [[ "$2" != "rw" && "$2" != "sw" && "$2" != "rr" && \
      "$2" != "sr" && ! "$2" =~ ^(rw|randrw)([0-9]{1,2})?$ ]]; then     
    echo "error: $2, Please set valid rw_mode!"
    echo "Usage: $0 filename rw_mode size qd numjobs bs disk_model output_format <runtime>"   
    exit 1 
fi
# check size
if ! [[ "$3" =~ ^[0-9]+$ ]] && \
   ! [[ "$3" =~ ^[0-9]+[kKmMgGtT%]$ ]] ; then         
    echo "error: $3, Please set valid size!" 
    echo "Usage: $0 filename rw_mode size qd numjobs bs disk_model output_format <runtime>"
    exit 1
fi
# check qd or numjobs
if ! [[ "$4" =~ ^-?[0-9]+$ ]] || ! [[ "$5" =~ ^-?[0-9]+$ ]]; then     
    echo "error: qd=$4, numjobs=$5, Please set valid qd or numjobs!" 
    echo "Usage: $0 filename rw_mode size qd numjobs bs disk_model output_format <runtime>"    
    exit 1 
fi
# check bs
if ! [[ "$bs" =~ ^[0-9]+[KkMm]?$ ]] && ! [[ "$bs" =~ ^[0-9]+(KiB|MiB)$ ]]; then     
    echo "error: qd=$6, Please set valid bs!" 
    echo "Usage: $0 filename rw_mode size qd numjobs bs disk_model output_format <runtime>"    
    exit 1 
fi
# check output-format
# if [[ ! "$8" =~ ^(normal|terse|json|json+)$ ]] && [[ ! "$8" =~ ^(normal|terse|json|json\+|normal,terse|terse,normal|terse,json|json,terse|normal,json|json,normal|normal,json\+|json\+,normal|terse,json\+|json\+,terse|terse,json\+|json\+,terse)$ ]]; then
#     echo "error: output-format=$8, Please set valid output-format!" 
#     echo "Usage: $0 filename rw_mode size qd numjobs bs disk_model output_format <runtime>"    
#     exit 1
# fi
      

OUTPUT_DIR="test_result"
mkdir -p "$OUTPUT_DIR"

# fio-3.28-0RxJ0000-read-10G-1-1-4K-100s
# fio_version-disk_model-rw_mode-size-qd-numjobs-bs-runtime

# FIO scripts
FIO_CMD+=" --name=$fio_version-$disk_model-$rw_mode-$size-$qd-$numjobs-$bs \
--filename=$filename \
--rw=$rw_mode \
--bs=$bs \
--size=$size \
--runtime=$runtime \
--ioengine=libaio \
--direct=1 \
--iodepth=$qd \
--numjobs=$numjobs \
--output-format=$output_format \
--group_reporting=1 \
--ramp_time=0 \
--output=$OUTPUT_DIR/$fio_version-$disk_model-$2-$size-qd$qd-num$numjobs-$bs-$runtime-WT.txt"

#--status-interval=$LOG_INTERVAL


eval "$FIO_CMD"
# echo "Running command: $FIO_CMD"
echo "Test: $fio_version-$disk_model-$2-$size-qd$qd-num$numjobs-$bs-$runtime over!"