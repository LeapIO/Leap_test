#!/bin/bash
MODE=$1
shift
FILENAME=$1
DISK_MODEL=$2
SIZE=$3
RW_MODE=$6 #sr 
#TO DO hyh
if [ "$RW_MODE" = "sw" ] || [ "$RW_MODE" = "rw" ]; then
  RW_MODE_FUL="write:"
elif [ "$RW_MODE" = "sr" ] || [ "$RW_MODE" = "rr" ]; then
  RW_MODE_FUL="read:"
fi

BS_LIST=("4k" "8k" "16k" "32k" "64k" "128k" "256k" "1024k")
QD_LIST=(1 4 8 32 64 256)
NUMJOBS_LIST=(1 4 8 16 32)
# 全条带逻辑
dev_name=$(basename "$FILENAME")
rotational_path="/sys/block/$dev_name/queue/rotational"
if [[ -f "$rotational_path" ]]; then
    rotational=$(cat "$rotational_path")
    #echo "Device $dev_name rotational = $rotational"
    if [[ "$rotational" -eq 1 ]]; then
        STRIP_SIZE="256K"
        strip_num=${STRIP_SIZE%K}
    elif [[ "$rotational" -eq 0 ]]; then
        STRIP_SIZE="64K"
        strip_num=${STRIP_SIZE%K}
    fi
fi

if [[ "$DISK_MODEL" =~ ^([0-9]+)R([0-9])J ]]; then
    n="${BASH_REMATCH[1]}"
    t="${BASH_REMATCH[2]}"
    case "$t" in
        0)
            # STRIPE_SIZE=$((n * strip_num))
            # bs_value="${result}K"
            # BS_LIST+=("$bs_value")
            ;;
        5)
            STRIPE_SIZE=$(((n - 1) * strip_num))
            bs_value="${STRIPE_SIZE}K"
            BS_LIST+=("$bs_value")
            ;;
        6)
            STRIPE_SIZE=$(((n - 2) * strip_num))
            bs_value="${STRIPE_SIZE}K"
            BS_LIST+=("$bs_value")
            ;;
        x)
            echo "JBOD,对齐参数设置为:$ALIGN"
            ;;
        *)
            echo "其他raid级别"
            ;;
    esac
else
    echo "请检查disk_model, 未知RAID级别和成员盘数"
fi

output_format=normal,json+
runtime=3000



echo "$MODE"
if [ "$MODE" = "31" ]; then
  if [ $# -lt 6 ]; then
    echo "ERROR  : 模式31需要参数: filename disk_model size numjobs bs rw"
    exit 1
  fi
  NUMJOBS=$5
  BS=$4
  echo > data/qd_loop
  for QD in "${QD_LIST[@]}"; do
    #echo $QD
    ./scripts/fio_standard.sh $FILENAME $RW_MODE $SIZE $QD $NUMJOBS $BS $DISK_MODEL $output_format $runtime 
    
    echo -n "rw=$RW_MODE, qd=$QD, bs=$BS, num=$NUMJOBS, " >> data/qd_loop
    #提取BW
    cat test_result/fio-3.28-$DISK_MODEL-$RW_MODE-$SIZE-qd$QD-num$NUMJOBS-$BS-$runtime-WT.txt \
      | grep "$RW_MODE_FUL" | awk -F '[()]' '{print $2}' | tr -d '\n' >> data/qd_loop
    echo -n ", " >> data/qd_loop
    #提取IOPS
    cat test_result/fio-3.28-$DISK_MODEL-$RW_MODE-$SIZE-qd$QD-num$NUMJOBS-$BS-$runtime-WT.txt \
      | grep "$RW_MODE_FUL" | sed -n 's/.*IOPS=\([^,]*\),.*/\1/p' | tr -d '\n' >> data/qd_loop
    echo -n ", " >> data/qd_loop
    #./leap_test 31 /dev/sda 4R5J0001 1G 1024K 1 sw
    cat test_result/fio-3.28-$DISK_MODEL-$RW_MODE-$SIZE-qd$QD-num$NUMJOBS-$BS-$runtime-WT.txt \
        | grep "lat (" | sed -n '3p' |awk '{ match($0, /lat \(([^)]+)\).*avg=([0-9.]+)[, ]/, m);
        print m[2], m[1]}' | tr -d '\n' >> data/qd_loop
    echo  >> data/qd_loop 

  done
  python3 ./scripts/plot.py data/qd_loop qd
elif [ "$MODE" = "32" ]; then
  if [ $# -lt 6 ]; then
    echo "ERROR :  模式32需要参数: filename disk_model size qd numjobs rw"
    exit 1
  fi

  QD=$4
  NUMJOBS=$5
  echo > data/bs_loop
  for BS in "${BS_LIST[@]}"; do
      ./scripts/fio_standard.sh $FILENAME $RW_MODE $SIZE $QD $NUMJOBS $BS $DISK_MODEL $output_format $runtime 
      echo -n "rw=$RW_MODE, qd=$QD, bs=$BS, num=$NUMJOBS, " >> data/bs_loop
      cat test_result/fio-3.28-$DISK_MODEL-$RW_MODE-$SIZE-qd$QD-num$NUMJOBS-$BS-$runtime-WT.txt \
        | grep "$RW_MODE_FUL" | awk -F '[()]' '{print $2}' | tr -d '\n' >> data/bs_loop
      echo -n ", " >> data/bs_loop
      #提取IOPS
      cat test_result/fio-3.28-$DISK_MODEL-$RW_MODE-$SIZE-qd$QD-num$NUMJOBS-$BS-$runtime-WT.txt \
        | grep "$RW_MODE_FUL" | sed -n 's/.*IOPS=\([^,]*\),.*/\1/p' | tr -d '\n' >> data/bs_loop
      echo -n ", " >> data/bs_loop
      cat test_result/fio-3.28-$DISK_MODEL-$RW_MODE-$SIZE-qd$QD-num$NUMJOBS-$BS-$runtime-WT.txt \
        | grep "lat (" | sed -n '3p' |awk '{ match($0, /lat \(([^)]+)\).*avg=([0-9.]+)[, ]/, m);
        print m[2], m[1]}' | tr -d '\n' >> data/bs_loop
      echo  >> data/bs_loop
  done
  python3 ./scripts/plot.py data/bs_loop bs
elif [ "$MODE" = "33" ]; then
  if [ $# -lt 6 ]; then
    echo "ERROR  :  模式33需要参数: filename disk_model size qd bs rw"
    exit 1
  fi
  QD=$4
  BS=$5
  echo > data/num_loop
  for NUMJOBS in "${NUMJOBS_LIST[@]}"; do
    ./scripts/fio_standard.sh $FILENAME $RW_MODE $SIZE $QD $NUMJOBS $BS $DISK_MODEL $output_format $runtime
    echo -n "rw=$RW_MODE, qd=$QD, bs=$BS, num=$NUMJOBS, " >> data/num_loop
    cat test_result/fio-3.28-$DISK_MODEL-$RW_MODE-$SIZE-qd$QD-num$NUMJOBS-$BS-$runtime-WT.txt \
      | grep "$RW_MODE_FUL" | awk -F '[()]' '{print $2}' | tr -d '\n' >> data/num_loop
    echo -n ", " >> data/num_loop
    cat test_result/fio-3.28-$DISK_MODEL-$RW_MODE-$SIZE-qd$QD-num$NUMJOBS-$BS-$runtime-WT.txt \
      | grep "$RW_MODE_FUL" | sed -n 's/.*IOPS=\([^,]*\),.*/\1/p' | tr -d '\n' >> data/num_loop
    echo -n ", " >> data/num_loop
    cat test_result/fio-3.28-$DISK_MODEL-$RW_MODE-$SIZE-qd$QD-num$NUMJOBS-$BS-$runtime-WT.txt \
        | grep "lat (" | sed -n '3p' |awk '{ match($0, /lat \(([^)]+)\).*avg=([0-9.]+)[, ]/, m);
        print m[2], m[1]}' | tr -d '\n' >> data/num_loop
    echo  >> data/num_loop

  done
  python3 ./scripts/plot.py data/num_loop num
else
  echo "ERROR 不支持：$MODE (应为 31 / 32 / 33)"
  exit 1
fi