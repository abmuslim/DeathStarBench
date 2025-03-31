from prometheus_client import start_http_server, Summary
import time
import re

# Use Summary to track request durations
LATENCY_SUMMARY = Summary('nginx_rt_latency_seconds', 'Summary of request latency')

LOG_PATH = "/var/log/nginx/access.log"

def tail_log(path):
    with open(path, "r") as f:
        f.seek(0, 2)
        while True:
            line = f.readline()
            if not line:
                time.sleep(0.1)
                continue
            yield line

def extract_latency(line):
    match = re.search(r'rt=(\d+\.\d+)', line)
    if match:
        return float(match.group(1))
    return None

if __name__ == "__main__":
    start_http_server(8000)
    print("🚀 Exporter running at :8000/metrics")
    for line in tail_log(LOG_PATH):
        latency = extract_latency(line)
        if latency is not None:
            LATENCY_SUMMARY.observe(latency)

