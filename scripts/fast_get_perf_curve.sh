#!/bin/bash

filename=$1
RW_MODES=("rr" "rw" "sr" "sw")

#RW_MODES=("rr" "rw" "sr" "sw" "randrw30" "rw50")
SIZE=("1G")
dev_name=$(basename "$filename")
rotational_path="/sys/block/$dev_name/queue/rotational"
if [[ -f "$rotational_path" ]]; then
    rotational=$(cat "$rotational_path")
    echo "Device $dev_name rotational = $rotational"
    if [[ "$rotational" -eq 1 ]]; then
        echo "$dev_name is HDD"
        SIZE=("1G")
    elif [[ "$rotational" -eq 0 ]]; then
        echo "$dev_name is SSD"
        SIZE=("1G")
    else
        echo "Unknown rotational value for $dev_name: $rotational"
    fi
else
    echo "Cannot find rotational info for $dev_name, set SIZE=1G"
fi

IODEPTHS=("1" "4" "64" "256")
NUMJOBS=("1")
BS=("4K" "8K" "16K" "32K" "64K" "128K" "256K" "1024K")

disk_model=$2
output_format=normal,json+
runtime=3000

echo  > ../data/curve
for rw_mode in "${RW_MODES[@]}"; do
    if [ "$rw_mode" = "sw" ] || [ "$rw_mode" = "rw" ]; then
        RW_MODE_FUL="write:"
    elif [ "$rw_mode" = "sr" ] || [ "$rw_mode" = "rr" ]; then
        RW_MODE_FUL="read:"
    fi
    for block_size in "${BS[@]}"; do
        for iodepths in "${IODEPTHS[@]}"; do
            for numjobs in "${NUMJOBS[@]}"; do
                for size in "${SIZE[@]}"; do
                #echo "$filename, $disk_model"
                #echo "fio_standar $filename $rw_mode $size $iodepths $numjobs $block_size $disk_model $output_format $runtime"
                ./fio_standard.sh $filename $rw_mode $size $iodepths $numjobs $block_size $disk_model $output_format $runtime
                # to do hyh
                # 存放到data/curve
                # rw=sw, qd=4, bs=256K, num=1, 1120MB/s, 4271, 930.80 usec
                echo -n "rw=$rw_mode, qd=$iodepths, bs=$block_size, num=$numjobs, " >> ../data/curve
                cat test_result/fio-3.28-$disk_model-$rw_mode-$size-qd$iodepths-num$numjobs-$block_size-$runtime-WT.txt \
                    | grep "$RW_MODE_FUL" | awk -F '[()]' '{print $2}' | tr -d '\n' >> ../data/curve
                echo -n ", " >> ../data/curve
                cat test_result/fio-3.28-$disk_model-$rw_mode-$size-qd$iodepths-num$numjobs-$block_size-$runtime-WT.txt \
                    | grep "$RW_MODE_FUL" | sed -n 's/.*IOPS=\([^,]*\),.*/\1/p' | tr -d '\n' >> ../data/curve
                echo -n ", " >> ../data/curve
                cat test_result/fio-3.28-$disk_model-$rw_mode-$size-qd$iodepths-num$numjobs-$block_size-$runtime-WT.txt \
                    | grep "lat (" | sed -n '3p' |awk '{ match($0, /lat \(([^)]+)\).*avg=([0-9.]+)[, ]/, m);
                    print m[2], m[1]}'  >> ../data/curve
                done
            done
        done
    done
done

echo "All tests completed. Results are stored in ./test_result/"

# todo
# ./parse.sh > log 
# python3 plot.py bw log