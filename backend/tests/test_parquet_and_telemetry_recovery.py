import os
import glob
import time
import uuid
import threading
import pytest
from app.data_engineering.engine import DataEngineeringEngine


def test_parquet_partitioned_storage_and_append_integrity(tmp_path):
    """
    Priority 1 Test:
    Verifies that batches create separate immutable Parquet partition files,
    existing telemetry is never overwritten, and DuckDB contains all records.
    """
    engine = DataEngineeringEngine(lakehouse_path=str(tmp_path))
    session_id = str(uuid.uuid4())
    course_id = "CSE-401"

    # Batch 1: 3 records
    events_1 = [
        {
            "session_id": session_id,
            "course_id": course_id,
            "student_id": f"student-{i}",
            "roll_number": f"CB.EN.U4CCE2200{i}",
            "device_id": f"00:11:22:33:44:0{i}",
            "rssi_dbm": -65 - i,
            "tx_power": -59,
            "biometric_verified": True,
            "packet_count": 1,
        }
        for i in range(1, 4)
    ]
    ingested_1 = engine.ingest_telemetry_batch(events_1)
    assert ingested_1 == 3

    # Check partition files
    partitions_dir = os.path.join(str(tmp_path), "partitions")
    parquet_files_1 = glob.glob(os.path.join(partitions_dir, "*.parquet"))
    assert len(parquet_files_1) == 1

    # Batch 2: 2 records
    events_2 = [
        {
            "session_id": session_id,
            "course_id": course_id,
            "student_id": f"student-{i}",
            "roll_number": f"CB.EN.U4CCE2200{i}",
            "device_id": f"00:11:22:33:44:0{i}",
            "rssi_dbm": -68,
            "tx_power": -59,
            "biometric_verified": True,
            "packet_count": 2,
        }
        for i in range(4, 6)
    ]
    ingested_2 = engine.ingest_telemetry_batch(events_2)
    assert ingested_2 == 2

    # Verify a NEW partition file was added, preserving the previous partition untouched
    parquet_files_2 = glob.glob(os.path.join(partitions_dir, "*.parquet"))
    assert len(parquet_files_2) == 2
    assert parquet_files_1[0] in parquet_files_2


def test_duckdb_reload_persisted_telemetry_after_restart(tmp_path):
    """
    Priority 1 Test:
    Ensures that when a new DataEngineeringEngine instance starts up
    (simulating backend restart), all persisted Parquet telemetry is restored
    and available for compliance and analytics queries.
    """
    engine_v1 = DataEngineeringEngine(lakehouse_path=str(tmp_path))
    session_id = str(uuid.uuid4())
    course_id = "CSE-402"

    events = [
        {
            "session_id": session_id,
            "course_id": course_id,
            "student_id": f"student-{i}",
            "roll_number": f"CB.EN.U4CCE2201{i}",
            "device_id": f"00:AA:BB:CC:DD:0{i}",
            "rssi_dbm": -60 - i,
            "biometric_verified": True,
        }
        for i in range(5)
    ]
    engine_v1.ingest_telemetry_batch(events)

    # Verify engine_v1 has 5 records
    matrix_v1 = engine_v1.compute_compliance_matrix(course_id=course_id)
    assert len(matrix_v1) == 5

    # Simulate backend crash/restart: instantiate new engine pointing to same directory
    engine_v2 = DataEngineeringEngine(lakehouse_path=str(tmp_path))

    # Verify engine_v2 automatically reloaded all 5 records from Parquet partitions
    matrix_v2 = engine_v2.compute_compliance_matrix(course_id=course_id)
    assert len(matrix_v2) == 5
    assert {s["student_id"] for s in matrix_v2} == {f"student-{i}" for i in range(5)}


def test_interrupted_write_recovery(tmp_path):
    """
    Priority 1 Test:
    Simulates a partial/crashed write that left an unrenamed .tmp file.
    Verifies that the engine ignores leftover .tmp files and reliably reloads valid partitions.
    """
    partitions_dir = os.path.join(str(tmp_path), "partitions")
    os.makedirs(partitions_dir, exist_ok=True)

    # 1. Ingest valid batch
    engine = DataEngineeringEngine(lakehouse_path=str(tmp_path))
    events = [
        {
            "session_id": "s1",
            "course_id": "c1",
            "student_id": "st-1",
            "roll_number": "R1",
            "device_id": "d1",
            "rssi_dbm": -70,
            "biometric_verified": True,
        }
    ]
    engine.ingest_telemetry_batch(events)

    # 2. Simulate crashed write creating a corrupt .tmp file
    corrupt_tmp = os.path.join(partitions_dir, "batch_crashed_123.parquet.tmp")
    with open(corrupt_tmp, "wb") as f:
        f.write(b"CORRUPT_INCOMPLETE_DATA_CRASH")

    # 3. Re-init engine (restart)
    recovered_engine = DataEngineeringEngine(lakehouse_path=str(tmp_path))
    count = recovered_engine.con.execute("SELECT COUNT(*) FROM ble_telemetry_stream").fetchone()[0]
    assert count == 1


def test_concurrent_parquet_writes(tmp_path):
    """
    Priority 1 Test:
    Verifies that multiple concurrent ingestion workers can write batches
    simultaneously without file-lock collisions, corruption, or data loss.
    """
    engine = DataEngineeringEngine(lakehouse_path=str(tmp_path))
    num_threads = 6
    records_per_thread = 10
    errors = []

    def worker(worker_id: int):
        try:
            events = [
                {
                    "session_id": f"sess-worker-{worker_id}",
                    "course_id": "c-multi",
                    "student_id": f"student-w{worker_id}-{j}",
                    "roll_number": f"CB.EN.U4CCE{worker_id:02d}{j:02d}",
                    "device_id": f"00:00:00:{worker_id:02x}:{j:02x}:00",
                    "rssi_dbm": -65,
                    "biometric_verified": True,
                }
                for j in range(records_per_thread)
            ]
            engine.ingest_telemetry_batch(events)
        except Exception as e:
            errors.append(e)

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(num_threads)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert len(errors) == 0, f"Concurrent writes threw errors: {errors}"

    # Verify all partitions exist
    partitions = glob.glob(os.path.join(str(tmp_path), "partitions", "*.parquet"))
    assert len(partitions) == num_threads

    # Verify total records across restart
    fresh_engine = DataEngineeringEngine(lakehouse_path=str(tmp_path))
    total_count = fresh_engine.con.execute("SELECT COUNT(*) FROM ble_telemetry_stream").fetchone()[0]
    assert total_count == num_threads * records_per_thread
