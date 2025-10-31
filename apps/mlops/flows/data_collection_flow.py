"""
Data Collection Flow - Collects metrics from Prometheus for memory leak detection.

This flow runs every 5 minutes to:
1. Query Prometheus for memory metrics
2. Transform and aggregate the data
3. Store in MinIO for later feature engineering
"""

from datetime import datetime, timedelta
from typing import List, Dict
import pandas as pd
from prefect import flow, task
from prefect.blocks.system import Secret
import requests
from io import BytesIO
import boto3


@task(retries=3, retry_delay_seconds=10)
def query_prometheus(query: str, start_time: datetime, end_time: datetime) -> pd.DataFrame:
    """Query Prometheus and return results as DataFrame."""

    # Prometheus endpoint (inside cluster)
    prometheus_url = "http://prometheus.monitoring:9090"

    params = {
        'query': query,
        'start': start_time.timestamp(),
        'end': end_time.timestamp(),
        'step': '60s'  # 1 minute resolution
    }

    response = requests.get(
        f"{prometheus_url}/api/v1/query_range",
        params=params,
        timeout=30
    )
    response.raise_for_status()

    data = response.json()

    if data['status'] != 'success':
        raise ValueError(f"Prometheus query failed: {data}")

    # Parse results into DataFrame
    records = []
    for result in data['data']['result']:
        metric_labels = result['metric']
        for timestamp, value in result['values']:
            records.append({
                'timestamp': datetime.fromtimestamp(timestamp),
                'value': float(value),
                **metric_labels
            })

    return pd.DataFrame(records)


@task
def collect_memory_metrics(start_time: datetime, end_time: datetime) -> Dict[str, pd.DataFrame]:
    """Collect all memory-related metrics for memory leak detection."""

    queries = {
        'memory_usage': 'container_memory_working_set_bytes{namespace!="kube-system"}',
        'memory_limit': 'kube_pod_container_resource_limits{resource="memory"}',
        'memory_request': 'kube_pod_container_resource_requests{resource="memory"}',
        'oom_kills': 'kube_pod_container_status_terminated_reason{reason="OOMKilled"}',
        'restarts': 'kube_pod_container_status_restarts_total',
        'request_rate': 'rate(traefik_service_requests_total[1m])'
    }

    metrics = {}
    for name, query in queries.items():
        df = query_prometheus(query, start_time, end_time)
        metrics[name] = df
        print(f"Collected {len(df)} records for {name}")

    return metrics


@task
def transform_metrics(metrics: Dict[str, pd.DataFrame]) -> pd.DataFrame:
    """Transform and join metrics into a single DataFrame."""

    # For now, just combine memory_usage with basic info
    df = metrics['memory_usage'].copy()

    # Add basic features
    df['hour'] = df['timestamp'].dt.hour
    df['day_of_week'] = df['timestamp'].dt.dayofweek

    # Round timestamp to nearest minute for joining
    df['timestamp_rounded'] = df['timestamp'].dt.round('1min')

    print(f"Transformed data: {len(df)} rows, {len(df.columns)} columns")
    print(f"Time range: {df['timestamp'].min()} to {df['timestamp'].max()}")

    return df


@task(retries=2)
def write_to_minio(df: pd.DataFrame, bucket: str = "metrics") -> str:
    """Write DataFrame to MinIO as Parquet."""

    # MinIO connection
    s3_client = boto3.client(
        's3',
        endpoint_url='http://minio.minio:9000',
        aws_access_key_id='minioadmin',
        aws_secret_access_key='minioadmin123'
    )

    # Ensure bucket exists
    try:
        s3_client.head_bucket(Bucket=bucket)
    except:
        s3_client.create_bucket(Bucket=bucket)

    # Generate filename with timestamp
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"memory_metrics/{timestamp}.parquet"

    # Write DataFrame to Parquet in memory
    buffer = BytesIO()
    df.to_parquet(buffer, index=False, compression='snappy')
    buffer.seek(0)

    # Upload to MinIO
    s3_client.upload_fileobj(buffer, bucket, filename)

    print(f"Written {len(df)} rows to s3://{bucket}/{filename}")
    return filename


@flow(name="data-collection", log_prints=True)
def data_collection_flow(lookback_minutes: int = 5):
    """
    Main data collection flow.

    Args:
        lookback_minutes: How many minutes of data to collect (default: 5)
    """

    end_time = datetime.now()
    start_time = end_time - timedelta(minutes=lookback_minutes)

    print(f"Collecting data from {start_time} to {end_time}")

    # Extract
    metrics = collect_memory_metrics(start_time, end_time)

    # Transform
    transformed_df = transform_metrics(metrics)

    # Load
    if len(transformed_df) > 0:
        filename = write_to_minio(transformed_df)
        print(f"✅ Data collection complete: {filename}")
    else:
        print("⚠️ No data collected")

    return transformed_df


if __name__ == "__main__":
    # For local testing
    data_collection_flow(lookback_minutes=10)
