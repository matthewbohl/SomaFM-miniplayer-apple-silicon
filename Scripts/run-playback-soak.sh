#!/bin/bash
set -u
set -o pipefail

cd "$(dirname "$0")/.."

duration="4h"
cycles="60"
station="groovesalad"
sample_interval="60"
channel_timeout="60"
leak_timeout="120"
max_growth_per_hour="1"
max_final_growth="10"
max_final_ratio="0.10"
max_leaked_bytes="65536"
max_stream_url_roots_per_start="1.5"
max_stream_url_root_overhead="5"
results_dir=""

usage() {
    cat <<'EOF'
Usage: Scripts/run-playback-soak.sh [options]

Options:
  --duration VALUE                 Total run time in seconds, or with m/h suffix (default: 4h)
  --cycles COUNT                   Number of playback lifecycle cycles (default: 60)
  --station ID                     Initial SomaFM station ID (default: groovesalad)
  --sample-interval SECONDS        Process-memory sampling interval (default: 60)
  --channel-timeout SECONDS        Channel-list startup timeout (default: 60)
  --leak-timeout SECONDS           External leak-check timeout (default: 120)
  --max-growth-mb-per-hour VALUE   Maximum footprint trend after warmup (default: 1)
  --max-final-growth-mb VALUE      Minimum final paused footprint allowance (default: 10)
  --max-final-growth-ratio VALUE   Relative final paused footprint allowance (default: 0.10)
  --max-leaked-bytes BYTES         Maximum bytes reported by leaks (default: 65536)
  --max-stream-url-roots-per-start VALUE
                                     Maximum URL-root ratio (default: 1.5)
  --max-stream-url-root-overhead COUNT
                                     Fixed roots allowed beyond the ratio (default: 5)
  --results-dir PATH               Result directory (default: timestamp under SoakResults)
  --help                           Show this help
EOF
}

require_value() {
    if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        echo "error: $1 requires a value" >&2
        usage >&2
        exit 2
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --duration) require_value "$@"; duration="$2"; shift 2 ;;
        --cycles) require_value "$@"; cycles="$2"; shift 2 ;;
        --station) require_value "$@"; station="$2"; shift 2 ;;
        --sample-interval) require_value "$@"; sample_interval="$2"; shift 2 ;;
        --channel-timeout) require_value "$@"; channel_timeout="$2"; shift 2 ;;
        --leak-timeout) require_value "$@"; leak_timeout="$2"; shift 2 ;;
        --max-growth-mb-per-hour) require_value "$@"; max_growth_per_hour="$2"; shift 2 ;;
        --max-final-growth-mb) require_value "$@"; max_final_growth="$2"; shift 2 ;;
        --max-final-growth-ratio) require_value "$@"; max_final_ratio="$2"; shift 2 ;;
        --max-leaked-bytes) require_value "$@"; max_leaked_bytes="$2"; shift 2 ;;
        --max-stream-url-roots-per-start) require_value "$@"; max_stream_url_roots_per_start="$2"; shift 2 ;;
        --max-stream-url-root-overhead) require_value "$@"; max_stream_url_root_overhead="$2"; shift 2 ;;
        --results-dir) require_value "$@"; results_dir="$2"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

duration_seconds() {
    local value="$1"
    local number multiplier
    case "$value" in
        *h) number="${value%h}"; multiplier=3600 ;;
        *m) number="${value%m}"; multiplier=60 ;;
        *s) number="${value%s}"; multiplier=1 ;;
        *) number="$value"; multiplier=1 ;;
    esac
    case "$number" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$number" -gt 0 ] || return 1
    echo $((number * multiplier))
}

if ! duration_seconds_value=$(duration_seconds "$duration"); then
    echo "error: --duration must be a positive integer with an optional s, m, or h suffix" >&2
    exit 2
fi
case "$cycles" in
    ''|*[!0-9]*) echo "error: --cycles must be a positive integer" >&2; exit 2 ;;
esac
if [ "$cycles" -le 0 ]; then
    echo "error: --cycles must be a positive integer" >&2
    exit 2
fi
case "$max_leaked_bytes" in
    ''|*[!0-9]*) echo "error: --max-leaked-bytes must be a nonnegative integer" >&2; exit 2 ;;
esac
case "$max_stream_url_root_overhead" in
    ''|*[!0-9]*) echo "error: --max-stream-url-root-overhead must be a nonnegative integer" >&2; exit 2 ;;
esac
if ! awk -v value="$max_stream_url_roots_per_start" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value > 0) }'; then
    echo "error: --max-stream-url-roots-per-start must be a positive number" >&2
    exit 2
fi

if [ -z "$results_dir" ]; then
    results_dir="SoakResults/$(date '+%Y%m%d-%H%M%S')"
fi
if [ -d "$results_dir" ] && [ -n "$(find "$results_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    echo "error: --results-dir must be empty: $results_dir" >&2
    exit 2
fi
mkdir -p "$results_dir"
results_dir=$(cd "$results_dir" && pwd)
derived_data="/private/tmp/SomaFM-Soak-DerivedData"

Scripts/check-public-repo-safety.sh

echo "Building dedicated Soak configuration..."
xcodebuild \
    -project SomaFM.xcodeproj \
    -scheme SomaFM \
    -configuration Soak \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data" \
    CODE_SIGN_IDENTITY= \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tee "$results_dir/build.log"
build_status=${PIPESTATUS[0]}
if [ "$build_status" -ne 0 ]; then
    echo "error: Soak build failed; see $results_dir/build.log" >&2
    exit "$build_status"
fi

app_binary="$derived_data/Build/Products/Soak/SomaFM miniplayer.app/Contents/MacOS/SomaFM miniplayer"
if [ ! -x "$app_binary" ]; then
    echo "error: built application executable was not found at $app_binary" >&2
    exit 1
fi

# Give the local diagnostic tool permission to inspect this unsigned test-only build.
/usr/bin/codesign \
    --force \
    --sign - \
    --entitlements Config/Soak.entitlements \
    "$derived_data/Build/Products/Soak/SomaFM miniplayer.app"

app_pid=""
cleanup() {
    if [ -n "$app_pid" ] && kill -0 "$app_pid" 2>/dev/null; then
        kill "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

echo "Running $cycles lifecycle cycles for $duration_seconds_value seconds..."
SOMAFM_SOAK_ENABLED=1 \
SOMAFM_SOAK_RESULTS_DIR="$results_dir" \
SOMAFM_SOAK_DURATION="$duration_seconds_value" \
SOMAFM_SOAK_CYCLES="$cycles" \
SOMAFM_SOAK_STATION="$station" \
SOMAFM_SOAK_SAMPLE_INTERVAL="$sample_interval" \
SOMAFM_SOAK_CHANNEL_TIMEOUT="$channel_timeout" \
SOMAFM_SOAK_LEAK_TIMEOUT="$leak_timeout" \
SOMAFM_SOAK_MAX_GROWTH_MB_PER_HOUR="$max_growth_per_hour" \
SOMAFM_SOAK_MAX_FINAL_GROWTH_MB="$max_final_growth" \
SOMAFM_SOAK_MAX_FINAL_GROWTH_RATIO="$max_final_ratio" \
    "$app_binary" >"$results_dir/app.log" 2>&1 &
app_pid=$!

started_at=$(date +%s)
deadline=$((started_at + duration_seconds_value + channel_timeout + leak_timeout + 300))
while kill -0 "$app_pid" 2>/dev/null && [ ! -f "$results_dir/ready-for-leak-check" ]; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "error: soak driver exceeded its watchdog deadline" >&2
        exit 1
    fi
    sleep 1
done

if kill -0 "$app_pid" 2>/dev/null && [ -f "$results_dir/ready-for-leak-check" ]; then
    echo "Capturing leak report..."
    /usr/bin/leaks "$app_pid" >"$results_dir/leaks.txt" 2>&1
    touch "$results_dir/leak-check-complete"
else
    echo "error: application exited before requesting its leak check" >&2
fi

wait "$app_pid"
app_status=$?
app_pid=""

leaked_bytes=$(awk '/leaks for [0-9]+ total leaked bytes/ { for (i = 1; i <= NF; i++) if ($i == "total") print $(i - 1) }' "$results_dir/leaks.txt" | tail -1)
stream_url_roots=$(awk '/ROOT LEAK: <CFString .*https:\/\/ice[0-9]+\.somafm\.com\// { count++ } END { print count + 0 }' "$results_dir/leaks.txt")
stream_starts=$(awk -F, 'NR > 1 { starts = $8 } END { print starts + 0 }' "$results_dir/samples.csv")
max_stream_url_roots=$(awk \
    -v starts="$stream_starts" \
    -v ratio="$max_stream_url_roots_per_start" \
    -v overhead="$max_stream_url_root_overhead" \
    'BEGIN { scaled = starts * ratio; ceiling = int(scaled); if (ceiling < scaled) ceiling++; print ceiling + overhead }')
if [ -z "$leaked_bytes" ] || grep -q -e 'not debuggable' -e 'Failed to map remote region' "$results_dir/leaks.txt"; then
    echo "error: leak check could not inspect the complete process" >&2
    exit 1
fi
if [ "$leaked_bytes" -gt "$max_leaked_bytes" ]; then
    echo "error: leak check reported $leaked_bytes bytes; limit is $max_leaked_bytes" >&2
    exit 1
fi
if [ "$stream_url_roots" -gt "$max_stream_url_roots" ]; then
    echo "error: leak check reported $stream_url_roots SomaFM stream URL roots after $stream_starts starts; limit is $max_stream_url_roots" >&2
    exit 1
fi
if [ "$app_status" -ne 0 ]; then
    echo "error: soak application failed; see $results_dir/summary.json and app.log" >&2
    exit "$app_status"
fi
if [ ! -f "$results_dir/summary.json" ] || ! grep -q '"passed" : true' "$results_dir/summary.json"; then
    echo "error: soak summary is missing or reports failure" >&2
    exit 1
fi

echo "Soak test passed with $leaked_bytes leaked bytes and $stream_url_roots stream URL roots after $stream_starts starts. Results: $results_dir"
