import sys
import re
import pandas as pd
import matplotlib.pyplot as plt
from datetime import datetime
import os

def parse_bandwidth(value):
    match = re.match(r"([\d\.]+)([KMG]?B)/s", value, re.IGNORECASE)
    if match:
        num = float(match[1])
        unit = match[2].upper()
        factor = {"KB": 1/1024, "MB": 1, "GB": 1024}
        return num * factor.get(unit, 1)
    return None

def parse_iops(value):
    match = re.match(r"([\d\.]+)([Kk]?)", value)
    if match:
        num = float(match[1])
        if match[2].lower() == 'k':
            num *= 1000
        return num
    return None

def parse_latency(value):
    match = re.match(r"([\d\.]+)\s*(ns|us|ms|s)", value, re.IGNORECASE)
    if match:
        num = float(match[1])
        unit = match[2].lower()
        factor = {"ns": 1e-3, "us": 1, "ms": 1e3, "s": 1e6}
        return num * factor.get(unit, 1)
    return None

def extract_field(fields, key):
    for field in fields:
        if field.strip().startswith(key + "="):
            return field.split("=")[1].strip()
    return None

def parse_bs(bs_str):
    match = re.match(r"(\d+)([KMG]?)", bs_str.upper())
    if match:
        num = int(match[1])
        unit = match[2]
        factor = {"": 1, "K": 1, "M": 1024, "G": 1024*1024}
        return num * factor.get(unit, 1)
    return None

def main(filename, x_type):
    data = []
    with open(filename, 'r') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) < 7:
                continue
            fields = parts[:4]
            bw_raw = parts[4].strip()
            iops_raw = parts[5].strip()
            lat_raw = parts[6].strip()

            entry = {
                'rw': extract_field(fields, 'rw'),
                'qd': extract_field(fields, 'qd'),
                'bs': extract_field(fields, 'bs'),
                'num': extract_field(fields, 'num'),
                'bandwidth_MBps': parse_bandwidth(bw_raw),
                'iops': parse_iops(iops_raw),
                'latency_us': parse_latency(lat_raw)
            }
            data.append(entry)

    df = pd.DataFrame(data)
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    os.makedirs('data/loop_pic_res', exist_ok=True)
    os.makedirs('data/curve_pic_res', exist_ok=True)
    if x_type == 'curve':
        df['qd'] = pd.to_numeric(df['qd'], errors='coerce')
        df['bs_val'] = df['bs'].apply(parse_bs)
        df = df.dropna(subset=['qd', 'bs_val'])

        for rw_mode in df['rw'].unique():
            df_rw = df[df['rw'] == rw_mode]
            qd_sorted = sorted(df_rw['qd'].unique())
            qd_pos = range(len(qd_sorted))
            qd_label_map = dict(zip(qd_sorted, qd_pos))

            for metric, ylabel in [('bandwidth_MBps', 'Bandwidth (MB/s)'),
                                   ('iops', 'IOPS'),
                                   ('latency_us', 'Latency (us)')]:
                plt.figure()
                for bs_val in sorted(df_rw['bs_val'].unique()):
                    df_bs = df_rw[df_rw['bs_val'] == bs_val]
                    df_bs = df_bs[df_bs['qd'].isin(qd_sorted)].copy()
                    df_bs['x'] = df_bs['qd'].map(qd_label_map)
                    df_bs = df_bs.sort_values(by='x')
                    plt.plot(df_bs['x'], df_bs[metric], marker='o', label=f"bs={df_bs['bs'].iloc[0]}")
                plt.title(f"{rw_mode} - {ylabel} vs qd")
                plt.xlabel("qd")
                plt.ylabel(ylabel)
                plt.xticks(qd_pos, [str(int(q)) for q in qd_sorted])
                plt.legend()
                plt.grid(True)
                plt.tight_layout()
                plt.savefig(f'data/curve_pic_res/{metric}_vs_qd_{rw_mode}_{timestamp}.png')
                print(f"图已保存: data/curve_pic_res/{metric}_vs_qd_{rw_mode}_{timestamp}.png")
    else:
        rw_mode = df['rw'].iloc[0] if not df.empty else 'unknown'
        
        if x_type not in ['qd', 'bs', 'num']:
            print(f"无效横坐标字段: {x_type}，应为 qd、bs、num 或 curve")
            sys.exit(1)

        if x_type in ['qd', 'num']:
            df[x_type] = pd.to_numeric(df[x_type], errors='coerce')
            df = df.dropna(subset=[x_type])
            df = df.sort_values(by=x_type)
            x_vals = df[x_type].values
            x_labels = [str(int(x)) for x in x_vals]
        elif x_type == 'bs':
            df['bs_val'] = df['bs'].apply(parse_bs)
            df = df.dropna(subset=['bs_val'])
            df = df.sort_values(by='bs_val')
            x_vals = df['bs_val'].values
            x_labels = df['bs'].tolist()

        for metric, ylabel in [('bandwidth_MBps', 'Bandwidth (MB/s)'),
                               ('iops', 'IOPS'),
                               ('latency_us', 'Latency (us)')]:
            plt.figure()
            x_pos = range(len(x_labels))  # 均匀位置
            plt.plot(x_pos, df[metric], marker='o')
            plt.xticks(x_pos, x_labels)
            if x_type == 'qd':
                bs_v = df['bs'].iloc[0] if not df.empty else 'unknown'
                num_v = df['num'].iloc[0] if not df.empty else 'unknown'
                plt.title(f'{rw_mode}-bs{bs_v}-num{num_v}-{ylabel} vs {x_type}')
            elif x_type == 'bs': 
                qd_v = df['qd'].iloc[0] if not df.empty else 'unknown'
                num_v = df['num'].iloc[0] if not df.empty else 'unknown'
                plt.title(f'{rw_mode}-qd{qd_v}-num{num_v}-{ylabel} vs {x_type}')
            elif x_type == 'bs': 
                qd_v = df['qd'].iloc[0] if not df.empty else 'unknown'
                bs_v = df['bs'].iloc[0] if not df.empty else 'unknown'
                plt.title(f'{rw_mode}-qd{qd_v}-bs{bs_v}-{ylabel} vs {x_type}')

            plt.xlabel(x_type)
            plt.ylabel(ylabel)
            plt.grid(True)
            plt.tight_layout()
            plt.savefig(f'data/loop_pic_res/{metric}_vs_{x_type}_{timestamp}.png')
            print(f"图已保存: data/loop_pic_res/{metric}_vs_{x_type}_{timestamp}.png")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("用法: python plot_perf_log.py <filename.csv> <qd|bs|num|curve>")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
