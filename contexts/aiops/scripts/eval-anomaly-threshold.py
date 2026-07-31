#!/usr/bin/env python3
"""
Dynamic Anomaly Threshold Evaluation Utility
Calculates dynamic confidence intervals (Moving Mean & StdDev) to eliminate alert noise.
"""

import sys
import math

def calculate_dynamic_threshold(data_points: list, sigma: float = 3.0) -> dict:
    if not data_points:
        return {"mean": 0, "std_dev": 0, "upper_bound": 0, "lower_bound": 0}
    
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
