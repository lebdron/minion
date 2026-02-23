#!/usr/bin/env python3

"""
Analyzes throughput, latency, and success stats from a JSON-serialized
Go result structure.

Supports two formats:
1. An older, aggregated format with pre-calculated fields like 'TotalThroughputOverTime'.
2. A newer, raw format with a nested structure (Locations -> Clients -> Interactions)
   from which statistics are calculated on the fly.

- Throughput stats can be sliced using --start-index and --end-index.
- Latency stats are based on calculated commit-submit times (in ms).
- Summary stats calculate the overall success percentage.
- Optionally generates a violin plot of latency distribution.
"""

import argparse
import json
import sys
import numpy as np
import math
import tarfile
import os
import fnmatch

# A check for plotting libraries to provide a helpful error message.
try:
    import matplotlib.pyplot as plt
    import seaborn as sns
    PLOT_LIBS_AVAILABLE = True
except ImportError:
    PLOT_LIBS_AVAILABLE = False

def preprocess_new_format_data(data: dict) -> dict:
    """
    Detects if the data is in the new, raw format and converts it to the old,
    aggregated format for processing. If already in the old format, returns it as is.
    """
    # If 'Locations' isn't a key, assume it's the old, pre-aggregated format.
    if "Locations" not in data or not isinstance(data["Locations"], list):
        return data

    print("New JSON format detected. Calculating aggregate statistics...")

    all_latencies_ms = []
    commit_times_sec = []
    success_count = 0
    fail_count = 0
    min_submit_time = float('inf')

    # Iterate through the entire structure to gather raw data
    for location in data.get("Locations", []):
        for client in location.get("Clients", []):
            for interaction in client.get("Interactions", []):
                submit_time = interaction.get("SubmitTime", -1)
                commit_time = interaction.get("CommitTime", -1)
                has_error = interaction.get("HasError", False)

                # An interaction is only counted if it was actually submitted.
                if submit_time < 0:
                    continue

                min_submit_time = min(min_submit_time, submit_time)

                # A successful transaction is one that has a commit time and no error.
                if commit_time > 0 and not has_error:
                    success_count += 1
                    latency_sec = commit_time - submit_time
                    all_latencies_ms.append(latency_sec * 1000)
                    commit_times_sec.append(commit_time)
                else:
                    fail_count += 1

    # --- Calculate Throughput Over Time ---
    throughput_per_second = []
    if commit_times_sec:
        # Determine the time range for the histogram bins (1-second windows)
        start_bin = math.floor(min_submit_time)
        end_bin = math.ceil(max(commit_times_sec))

        # Ensure at least one bin exists
        if end_bin <= start_bin:
            end_bin = start_bin + 1

        # Create bins from the start to the end time
        bins = np.arange(start_bin, end_bin + 1)

        # Use numpy.histogram to efficiently count commits in each 1s window
        counts, _ = np.histogram(commit_times_sec, bins=bins)
        throughput_per_second = counts.tolist()

    # Construct the dictionary in the old format
    aggregated_data = {
        "TotalSuccess": success_count,
        "TotalFails": fail_count,
        "AllTxLatencies": all_latencies_ms,
        "TotalThroughputOverTime": throughput_per_second
    }

    return aggregated_data

def generate_latency_plot(latencies_ms: list, output_filename: str):
    """Generates and saves a violin plot of the latency distribution."""
    if not PLOT_LIBS_AVAILABLE:
        print("\nPlotting libraries matplotlib and seaborn are not installed.", file=sys.stderr)
        print("Please install them to use the --plot feature:", file=sys.stderr)
        print("pip install matplotlib seaborn", file=sys.stderr)
        return

    if not isinstance(latencies_ms, list) or not latencies_ms:
        print("\nWarning: No latency data available to plot.", file=sys.stderr)
        return

    print(f"\nGenerating latency plot and saving to '{output_filename}'...")

    sns.set_theme(style="whitegrid")
    fig, ax = plt.subplots(figsize=(8, 6))

    # Create the violin plot
    sns.violinplot(y=latencies_ms, ax=ax, inner="box", color="skyblue")

    # Set titles and labels for clarity
    ax.set_title("Latency Distribution", fontsize=16, fontweight='bold')
    ax.set_ylabel("Latency (ms)", fontsize=12)
    ax.set_xlabel("All Transactions", fontsize=12)

    # Improve readability
    ax.grid(True, which='both', linestyle='--', linewidth=0.5)

    try:
        plt.savefig(output_filename, dpi=150, bbox_inches='tight')
        print("Plot successfully saved.")
    except Exception as e:
        print(f"Error saving plot: {e}", file=sys.stderr)
    finally:
        plt.close(fig) # Free up memory

def print_throughput_stats(data: dict, start_index: int, end_index: int | None):
    """Prints statistics for a specified slice of TotalThroughputOverTime."""
    print("--- Throughput Statistics ---")

    original_throughput_data = data.get("TotalThroughputOverTime")
    if not isinstance(original_throughput_data, list) or not original_throughput_data:
        print("  'TotalThroughputOverTime' not found or is empty. Skipping.")
        print("-----------------------------")
        return

    total_available_windows = len(original_throughput_data)

    if start_index < 0 or (end_index is not None and end_index < start_index):
        print(f"  Error: Invalid index range (start={start_index}, end={end_index}).", file=sys.stderr)
        return

    slice_end = (end_index + 1) if end_index is not None else None
    throughput_data_slice = original_throughput_data[start_index:slice_end]

    if not throughput_data_slice:
        print("  The specified slice resulted in an empty dataset. No stats to calculate.")
        return

    throughput_array = np.array(throughput_data_slice)
    local_nonzero_indices = np.where(throughput_array != 0)[0]

    first_nonzero_index = int(local_nonzero_indices[0] + start_index) if local_nonzero_indices.size > 0 else "N/A"
    last_nonzero_index = int(local_nonzero_indices[-1] + start_index) if local_nonzero_indices.size > 0 else "N/A"

    stats = { "Windows Analyzed": len(throughput_array), "First Non-Zero Window": first_nonzero_index,
              "Last Non-Zero Window": last_nonzero_index, "Average": np.mean(throughput_array),
              "Median": np.median(throughput_array), "Min": np.min(throughput_array), "Max": np.max(throughput_array),
              "Std Deviation": np.std(throughput_array), "Total Sum": np.sum(throughput_array) }

    actual_end_window = start_index + len(throughput_data_slice) - 1
    header = f"(Analyzing windows {start_index}-{actual_end_window} of {total_available_windows} Total)"
    print(header)

    for key, value in stats.items():
        if isinstance(value, str): 
            print(f"  {key:<23}: {value}")
        elif isinstance(value, int): 
            print(f"  {key:<23}: {value}")
        else: 
            print(f"  {key:<23}: {value:.2f}")
    print("-----------------------------")
    
def generate_throughput_plot(throughput_data: list, start_index: int, end_index: int | None, output_filename: str):
    """Generates and saves a line plot of throughput over time for the specified slice."""
    if not PLOT_LIBS_AVAILABLE:
        print("\nPlotting libraries matplotlib and seaborn are not installed.", file=sys.stderr)
        print("Please install them to use the plotting features:", file=sys.stderr)
        print("pip install matplotlib seaborn", file=sys.stderr)
        return

    if not isinstance(throughput_data, list) or not throughput_data:
        print("\nWarning: No throughput data available to plot.", file=sys.stderr)
        return

    if start_index < 0 or (end_index is not None and end_index < start_index):
        print(f"\nError: Invalid index range (start={start_index}, end={end_index}). Cannot generate plot.", file=sys.stderr)
        return

    slice_end = (end_index + 1) if end_index is not None else None
    throughput_data_slice = throughput_data[start_index:slice_end]

    if not throughput_data_slice:
        print("\nWarning: The specified slice resulted in an empty dataset. No plot generated.", file=sys.stderr)
        return

    x_values = np.arange(start_index, start_index + len(throughput_data_slice))
    y_values = np.array(throughput_data_slice)

    sns.set_theme(style="whitegrid")
    fig, ax = plt.subplots(figsize=(10, 6))

    ax.plot(x_values, y_values, marker='o', linestyle='-', color='blue')
    ax.set_title("Throughput Over Time", fontsize=16, fontweight='bold')
    ax.set_xlabel("Time Window Index", fontsize=12)
    ax.set_ylabel("Throughput (tx/s)", fontsize=12)
    ax.grid(True, which='both', linestyle='--', linewidth=0.5)

    try:
        plt.savefig(output_filename, dpi=150, bbox_inches='tight')
        print(f"Throughput plot successfully saved to '{output_filename}'.")
    except Exception as e:
        print(f"Error saving throughput plot: {e}", file=sys.stderr)
    finally:
        plt.close(fig) # Free up memory

def print_latency_stats(data: dict):
    """Prints statistics for AllTxLatencies, assuming units are in ms."""
    print("\n--- Latency Statistics ---")

    latencies_ms = data.get("AllTxLatencies")
    if not isinstance(latencies_ms, list) or not latencies_ms:
        print("  Latency data ('AllTxLatencies') not found or is empty. Skipping.")
        print("------------------------------------------------")
        return

    latency_array_ms = np.array(latencies_ms)
    stats = { "Transactions": len(latency_array_ms), "Average (ms)": np.mean(latency_array_ms),
              "Median (ms)": np.median(latency_array_ms), "Min (ms)": np.min(latency_array_ms),
              "Max (ms)": np.max(latency_array_ms), "Std Dev (ms)": np.std(latency_array_ms),
              "P95 (ms)": np.percentile(latency_array_ms, 95), "P99 (ms)": np.percentile(latency_array_ms, 99) }

    for key, value in stats.items():
        if isinstance(value, int): 
            print(f"  {key:<23}: {value}")
        else: 
            print(f"  {key:<23}: {value:.3f}")
    print("------------------------------------------------")

def print_summary_stats(data: dict):
    """Prints overall summary stats like success rate."""
    print("\n--- Overall Summary ---")
    success, fails = data.get("TotalSuccess"), data.get("TotalFails")
    if success is None or fails is None:
        print("  'TotalSuccess' or 'TotalFails' key not found. Skipping.")
        print("-----------------------")
        return

    total_tx = success + fails
    success_rate = (success / total_tx) * 100 if total_tx > 0 else 0.0

    print(f"  {'Total Transactions':<23}: {total_tx}")
    print(f"  {'Successful':<23}: {success}")
    print(f"  {'Failed':<23}: {fails}")
    print(f"  {'Success Rate':<23}: {success_rate:.2f}%")
    print("-----------------------")

def print_observer_stats(observer_data_list: list, blockchain_name: str | None, total_success: int):
    """Prints aggregated P2P bandwidth statistics from observer files."""
    if not observer_data_list:
        return

    # Identify node IPs to filter for P2P traffic (matching heatmap logic)
    node_ips = set()
    for data in observer_data_list:
        meta = data.get("experiment_metadata", {})
        if "own_ip" in meta:
            node_ips.add(meta["own_ip"])

    total_tx_kib = 0.0
    total_rx_kib = 0.0
    kib_conversion = 1024

    for data in observer_data_list:
        cumulative = data.get("remote_entity_bw", {}).get("cumulative_totals_bytes", {})
        for remote_ip, stats in cumulative.items():
            # Only count traffic if the remote is a known peer node
            if remote_ip in node_ips:
                total_tx_kib += stats.get("tx", 0) / kib_conversion
                total_rx_kib += stats.get("rx", 0) / kib_conversion

    print("\n--- Observer Network Stats (P2P Total) ---")
    print(f"  {'Total Sum (TX)':<23}: {total_tx_kib:,.2f} KiB")
    print(f"  {'Total Sum (RX)':<23}: {total_rx_kib:,.2f} KiB")

    tx_sizes = {
        "algorand": 250,
        "aptos": 310,
        "avalanche": 117,
        "sevm": 105,
        "solana": 215
    }

    if blockchain_name:
        b_name = blockchain_name.lower().strip()
        if b_name in tx_sizes:
            size = tx_sizes[b_name]
            # KiB -> Bytes -> Count
            tx_count = (total_tx_kib * 1024) / size
            rx_count = (total_rx_kib * 1024) / size
            print(f"  {'Tx-Equiv (TX)':<23}: {tx_count:,.0f} (assuming {size}B/tx)")
            print(f"  {'Tx-Equiv (RX)':<23}: {rx_count:,.0f} (assuming {size}B/tx)")

            if total_success > 0:
                ratio = tx_count / total_success
                print(f"  {'Tx-Equiv / Success':<23}: {ratio:.2f}")

    print("------------------------------------------")

def analyze_results(json_file_path: str, start_index: int, end_index: int | None, plot: bool = False):
    """Main function to orchestrate the analysis of the results file."""
    data = None
    observer_data_list = []
    blockchain_name = None

    try:
        # Check if the input is a tar.gz archive
        if json_file_path.endswith(".tar.gz"):
            print(f"Reading from tar archive '{json_file_path}'...")
            with tarfile.open(json_file_path, 'r:gz') as tar:
                # Iterate over all members to find relevant files
                for member in tar.getmembers():
                    if not member.isfile():
                        continue
                    
                    basename = os.path.basename(member.name)
                    
                    if basename == 'results.json':
                        with tar.extractfile(member) as f:
                            data = json.load(f)
                        print(f"  Found '{member.name}' in archive.")
                    elif basename == 'name.txt':
                        with tar.extractfile(member) as f:
                            blockchain_name = f.read().decode('utf-8').strip()
                        print(f"  Found '{member.name}' in archive ({blockchain_name}).")
                    elif fnmatch.fnmatch(basename, "observer-results-*.json"):
                        try:
                            with tar.extractfile(member) as f:
                                observer_data_list.append(json.load(f))
                        except Exception as e:
                            print(f"Warning: Could not load {member.name}: {e}", file=sys.stderr)

                if not data:
                    print(f"Error: Could not find a 'results.json' file inside '{json_file_path}'.", file=sys.stderr)
                    sys.exit(1)
        else:
            # Original logic for plain JSON files
            with open(json_file_path, 'r') as f:
                data = json.load(f)

            base_dir = os.path.dirname(json_file_path) or "."
            
            # Check for name.txt in directory
            name_path = os.path.join(base_dir, "name.txt")
            if os.path.exists(name_path):
                with open(name_path, 'r') as f:
                    blockchain_name = f.read().strip()

            # Check for observer files
            if os.path.isdir(base_dir):
                for fname in os.listdir(base_dir):
                    if fnmatch.fnmatch(fname, "observer-results-*.json"):
                        try:
                            with open(os.path.join(base_dir, fname), 'r') as f:
                                observer_data_list.append(json.load(f))
                        except Exception:
                            pass

    except FileNotFoundError:
        print(f"Error: The file '{json_file_path}' was not found.", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError:
        print("Error: The file content is not valid JSON.", file=sys.stderr)
        sys.exit(1)
    except tarfile.ReadError:
        print(f"Error: Could not read '{json_file_path}'. It may be a corrupted tar.gz file.", file=sys.stderr)
        sys.exit(1)

    # Pre-process the data. This handles both old and new formats.
    processed_data = preprocess_new_format_data(data)

    print_throughput_stats(processed_data, start_index, end_index)
    print_latency_stats(processed_data)
    print_summary_stats(processed_data)
    total_success = processed_data.get("TotalSuccess", 0)
    print_observer_stats(observer_data_list, blockchain_name, total_success)

    if plot:
        plot_prefix = os.path.splitext(os.path.basename(json_file_path))[0] + "_"
        generate_latency_plot(processed_data.get("AllTxLatencies"), f"results/{plot_prefix}latency_plot.pdf")
        generate_throughput_plot(processed_data.get("TotalThroughputOverTime"), start_index, end_index, f"results/{plot_prefix}throughput_plot.pdf")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Analyzes throughput, latency, and success stats from a results JSON file.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("json_file", type=str, help="Path to the JSON file containing the results.", nargs='?')
    parser.add_argument("--start-index", type=int, metavar="START", default=0,
                        help="Optional: Start throughput analysis from this window index (0-based).\nDefault is 0.")
    parser.add_argument("--end-index", type=int, metavar="END", default=None,
                        help="Optional: End throughput analysis at this window index (inclusive).\nDefault is the last window.")
    parser.add_argument("--plot", action="store_true",
                        help="Optional: Generate plots for latency and throughput.")
    parser.add_argument("--latest", action="store_true",
                        help="Optional: Analyze the most recently modified JSON file in the 'results' directory.")

    args = parser.parse_args()

    if args.latest:
        results_dir = "results"
        if not os.path.isdir(results_dir):
            print(f"Error: The directory '{results_dir}' does not exist.", file=sys.stderr)
            sys.exit(1)
        archives = [os.path.join(results_dir, f) for f in os.listdir(results_dir) if f.endswith(".tar.gz")]
        if not archives:
            print(f"Error: No log archive found in '{results_dir}'.", file=sys.stderr)
            sys.exit(1)
        latest_file = max(archives, key=os.path.getmtime)
        args.json_file = latest_file
    elif not args.json_file:
        print("Error: No JSON file specified. Use --latest to analyze the most recent file or provide a file path.", file=sys.stderr)
        parser.print_help()
        sys.exit(1)

    analyze_results(args.json_file, args.start_index, args.end_index, args.plot)
