#!/usr/bin/env python3
"""
FSx for Lustre Throughput Benchmark Script

This script runs a simple throughput benchmark against an FSx for Lustre filesystem.
It measures read and write throughput using dd and optional fio (if available).

Usage:
    python3 fsx_benchmark.py --fsx-mount /scratch --output /tmp/fsx_benchmark.json
"""

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime


def run_command(cmd, timeout=300):
    """Run a shell command and return the result."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", f"Command timed out after {timeout} seconds"
    except Exception as e:
        return -1, "", str(e)


def test_write_throughput(mount_point, size_mb=1024):
    """Test write throughput using dd."""
    test_file = os.path.join(mount_point, f"benchmark_write_{int(time.time())}.dat")

    cmd = f"dd if=/dev/zero of={test_file} bs=1M count={size_mb} conv=fdatasync 2>&1"
    returncode, stdout, stderr = run_command(cmd)

    if returncode != 0:
        return {"success": False, "error": stderr}

    # Parse dd output for throughput
    # Output format: "X+X records in\nX+X records out\nX bytes transferred in Y secs (Z bytes/sec)"
    throughput_line = [
        line for line in stdout.split("\n") if "bytes/sec" in line.lower()
    ]

    if throughput_line:
        # Extract bytes per second
        import re

        match = re.search(r"([\d.]+)\s*(?:bytes|KB|MB|GB)/s", throughput_line[0])
        if match:
            value = float(match.group(1))
            unit = match.group(2) if match.lastindex > 1 else "bytes"

            # Convert to MB/s
            if unit == "KB":
                value *= 0.001
            elif unit == "GB":
                value *= 1024
            # bytes is already in bytes, convert to MB/s
            elif unit == "bytes":
                value *= 1e-6

            return {
                "success": True,
                "operation": "write",
                "file_size_mb": size_mb,
                "throughput_mbps": round(value, 2),
                "throughput_mibps": round(value * 0.953674, 2),  # MiB/s
            }

    return {
        "success": False,
        "error": "Could not parse dd output for throughput",
        "raw_output": stdout,
    }


def test_read_throughput(mount_point, size_mb=1024):
    """Test read throughput using dd."""
    # Find the most recent write test file
    cmd = f"ls -t {mount_point}/benchmark_write_*.dat 2>/dev/null | head -1"
    returncode, stdout, stderr = run_command(cmd)

    if returncode != 0 or not stdout.strip():
        return {
            "success": False,
            "error": "No write test file found. Run write test first.",
        }

    test_file = stdout.strip()

    # Clear caches to get realistic read performance
    run_command("sync")

    cmd = f"dd if={test_file} of=/dev/null bs=1M 2>&1"
    returncode, stdout, stderr = run_command(cmd)

    # Clean up
    run_command(f"rm -f {test_file}")

    if returncode != 0:
        return {"success": False, "error": stderr}

    # Parse dd output for throughput
    throughput_line = [
        line for line in stdout.split("\n") if "bytes/sec" in line.lower()
    ]

    if throughput_line:
        import re

        match = re.search(r"([\d.]+)\s*(?:bytes|KB|MB|GB)/s", throughput_line[0])
        if match:
            value = float(match.group(1))
            unit = match.group(2) if match.lastindex > 1 else "bytes"

            # Convert to MB/s
            if unit == "KB":
                value *= 0.001
            elif unit == "GB":
                value *= 1024
            elif unit == "bytes":
                value *= 1e-6

            return {
                "success": True,
                "operation": "read",
                "file_size_mb": size_mb,
                "throughput_mbps": round(value, 2),
                "throughput_mibps": round(value * 0.953674, 2),
            }

    return {
        "success": False,
        "error": "Could not parse dd output for throughput",
        "raw_output": stdout,
    }


def test_sequential_write(mount_point, file_count=5, size_mb=512):
    """Test sequential write performance with multiple files."""
    results = []

    for i in range(file_count):
        test_file = os.path.join(mount_point, f"seq_write_{int(time.time())}_{i}.dat")
        cmd = f"dd if=/dev/zero of={test_file} bs=1M count={size_mb} 2>&1"
        returncode, stdout, stderr = run_command(cmd)

        if returncode == 0:
            results.append({"file": test_file, "success": True})
        else:
            results.append({"file": test_file, "success": False, "error": stderr})

    # Clean up
    for result in results:
        if result.get("success"):
            run_command(f"rm -f {result['file']}")

    return {
        "success": True,
        "files_tested": file_count,
        "file_size_mb": size_mb,
        "results": results,
    }


def test_sequential_read(mount_point, file_count=5, size_mb=512):
    """Test sequential read performance with multiple files."""
    results = []

    # Find recent test files
    cmd = f"ls -t {mount_point}/seq_write_*.dat 2>/dev/null | head -{file_count}"
    returncode, stdout, stderr = run_command(cmd)

    if returncode != 0 or not stdout.strip():
        return {"success": False, "error": "No sequential write test files found."}

    files = stdout.strip().split("\n")

    for test_file in files:
        if not test_file:
            continue
        cmd = f"dd if={test_file} of=/dev/null bs=1M 2>&1"
        returncode, stdout, stderr = run_command(cmd)

        if returncode == 0:
            results.append({"file": test_file, "success": True})
        else:
            results.append({"file": test_file, "success": False, "error": stderr})

    return {
        "success": True,
        "files_tested": len(files),
        "file_size_mb": size_mb,
        "results": results,
    }


def check_fsx_mount(mount_point):
    """Check if FSx is properly mounted."""
    # Check if mount point exists
    if not os.path.exists(mount_point):
        return {"success": False, "error": f"Mount point {mount_point} does not exist"}

    # Check if it's a Lustre filesystem
    cmd = f"df -T {mount_point} 2>&1"
    returncode, stdout, stderr = run_command(cmd)

    if returncode != 0:
        return {
            "success": False,
            "error": f"Could not determine filesystem type: {stderr}",
        }

    if "lustre" in stdout.lower():
        return {"success": True, "filesystem": "lustre", "mount_point": mount_point}
    else:
        return {
            "success": False,
            "error": f"Mount point is not a Lustre filesystem. Found: {stdout}",
        }


def main():
    parser = argparse.ArgumentParser(
        description="FSx for Lustre Throughput Benchmark Script"
    )
    parser.add_argument(
        "--fsx-mount",
        default="/scratch",
        help="Mount point for FSx filesystem (default: /scratch)",
    )
    parser.add_argument(
        "--output",
        default="/tmp/fsx_benchmark.json",
        help="Output file for benchmark results (default: /tmp/fsx_benchmark.json)",
    )
    parser.add_argument(
        "--quick", action="store_true", help="Run quick benchmark with smaller files"
    )
    parser.add_argument("--verbose", action="store_true", help="Show verbose output")

    args = parser.parse_args()

    # Check if running on an instance with FSx mounted
    mount_check = check_fsx_mount(args.fsx_mount)
    if not mount_check["success"]:
        print(f"ERROR: {mount_check['error']}")
        print("\nMake sure:")
        print("1. FSx is deployed with 'make fsx-up'")
        print("2. The instance has the FSx mounted at the specified mount point")
        print("3. The instance has network access to the FSx filesystem")
        sys.exit(1)

    print(f"FSx mount check passed: {mount_check['mount_point']}")

    # Determine test sizes
    if args.quick:
        write_size = 256  # MB
        read_size = 256  # MB
    else:
        write_size = 1024  # MB
        read_size = 1024  # MB

    results = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "mount_point": args.fsx_mount,
        "quick_mode": args.quick,
        "tests": {},
    }

    # Run benchmarks
    print("\n" + "=" * 60)
    print("Running FSx Throughput Benchmark")
    print("=" * 60)

    # Write throughput
    print("\n1. Testing write throughput...")
    write_result = test_write_throughput(args.fsx_mount, write_size)
    results["tests"]["write_throughput"] = write_result

    if write_result["success"]:
        print(f"   Write throughput: {write_result['throughput_mbps']} MB/s")
    else:
        print(f"   Write test failed: {write_result.get('error', 'Unknown error')}")

    # Read throughput (only if write succeeded)
    if write_result["success"]:
        print("\n2. Testing read throughput...")
        read_result = test_read_throughput(args.fsx_mount, read_size)
        results["tests"]["read_throughput"] = read_result

        if read_result["success"]:
            print(f"   Read throughput: {read_result['throughput_mbps']} MB/s")
        else:
            print(f"   Read test failed: {read_result.get('error', 'Unknown error')}")

    # Sequential write test
    print("\n3. Testing sequential write performance...")
    seq_write = test_sequential_write(args.fsx_mount, file_count=3, size_mb=256)
    results["tests"]["sequential_write"] = seq_write

    if seq_write["success"]:
        success_count = sum(1 for r in seq_write.get("results", []) if r.get("success"))
        print(
            f"   Sequential writes: {success_count}/{seq_write['files_tested']} files"
        )

    # Sequential read test
    if seq_write["success"]:
        print("\n4. Testing sequential read performance...")
        seq_read = test_sequential_read(args.fsx_mount, file_count=3, size_mb=256)
        results["tests"]["sequential_read"] = seq_read

        if seq_read["success"]:
            success_count = sum(
                1 for r in seq_read.get("results", []) if r.get("success")
            )
            print(
                f"   Sequential reads: {success_count}/{seq_read['files_tested']} files"
            )

    # Write results to file
    with open(args.output, "w") as f:
        json.dump(results, f, indent=2)

    print(f"\nBenchmark results written to: {args.output}")

    # Print summary
    print("\n" + "=" * 60)
    print("Benchmark Summary")
    print("=" * 60)

    if write_result["success"]:
        print(f"Write throughput:  {write_result['throughput_mbps']:>8.2f} MB/s")
    else:
        print(f"Write throughput:  N/A")

    if (
        "read_throughput" in results["tests"]
        and results["tests"]["read_throughput"]["success"]
    ):
        print(
            f"Read throughput:   {results['tests']['read_throughput']['throughput_mbps']:>8.2f} MB/s"
        )

    print(f"\nQuick mode: {'Yes' if args.quick else 'No'}")
    print(f"Output file: {args.output}")

    # Return exit code based on success
    if write_result["success"]:
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
