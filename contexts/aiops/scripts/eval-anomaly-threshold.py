#!/usr/bin/env python3
"""
Dynamic Anomaly Threshold Evaluation Utility
Calculates dynamic confidence intervals (Moving Mean & StdDev) to eliminate alert noise.
"""

import math

def calculate_dynamic_threshold(data_points: list, sigma: float = 3.0) -> dict:
    # 빈 입력도 정상 경로와 "같은 키 집합"을 돌려준다. 예전엔 키 4개만 반환해서
    # result["anomaly_count"] 같은 접근이 KeyError 로 죽었다 — 메트릭 조회가 빈 결과를
    # 내는 것은 운영에서 흔한 경로(대상 인스턴스 없음, 조회 구간에 데이터 없음)라
    # 호출자가 방어할 이유가 없는 자리에서 터진다.
    # noise_reduction_ratio 는 데이터가 없으면 줄일 노이즈도 없으므로 "0%" 로 둔다.
    if not data_points:
        return {
            "mean": 0,
            "std_dev": 0,
            "upper_bound": 0,
            "lower_bound": 0,
            "total_points": 0,
            "anomaly_count": 0,
            "noise_reduction_ratio": "0%",
        }


    mean = sum(data_points) / len(data_points)
    variance = sum((x - mean) ** 2 for x in data_points) / len(data_points)
    std_dev = math.sqrt(variance)
    
    upper_bound = mean + (sigma * std_dev)
    lower_bound = max(0.0, mean - (sigma * std_dev))
    
    anomalies = [x for x in data_points if x > upper_bound or x < lower_bound]
    
    return {
        "mean": round(mean, 2),
        "std_dev": round(std_dev, 2),
        "upper_bound": round(upper_bound, 2),
        "lower_bound": round(lower_bound, 2),
        "total_points": len(data_points),
        "anomaly_count": len(anomalies),
        "noise_reduction_ratio": f"{round((1 - len(anomalies)/len(data_points)) * 100, 1)}%"
    }

if __name__ == "__main__":
    # Sample Metric Values (e.g. CPU Utilization over 20 intervals)
    sample_metrics = [42.1, 44.5, 41.8, 43.0, 42.9, 45.1, 43.8, 44.0, 42.5, 91.2, 43.1, 42.8, 44.2, 43.0, 42.6]
    result = calculate_dynamic_threshold(sample_metrics, sigma=3.0)
    print("📈 Dynamic Threshold Analysis Result:")
    for k, v in result.items():
        print(f"  - {k}: {v}")
