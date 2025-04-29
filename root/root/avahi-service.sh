#!/bin/sh

# Function to clean up existing avahi-daemon processes
cleanup_avahi() {
    echo "Cleaning up existing avahi-daemon processes..."
    
    # Check for PID file in both possible locations
    if [ -f /var/run/avahi-daemon/pid ]; then
        PID=$(cat /var/run/avahi-daemon/pid)
        if kill -0 $PID 2>/dev/null; then
            echo "Killing avahi-daemon process with PID $PID"
            kill $PID
            # Wait for process to terminate
            for i in $(seq 1 5); do
                if ! kill -0 $PID 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            # Force kill if still running
            if kill -0 $PID 2>/dev/null; then
                echo "Force killing avahi-daemon process with PID $PID"
                kill -9 $PID
            fi
        else
            echo "Process with PID $PID from PID file does not exist or is not accessible"
        fi
        echo "Removing PID file /var/run/avahi-daemon/pid"
        rm -f /var/run/avahi-daemon/pid
    fi
    
    # Also check the incorrect location for backward compatibility
    if [ -f /var/run/avahi-daemon.pid ]; then
        echo "Found PID file at incorrect location /var/run/avahi-daemon.pid, removing"
        rm -f /var/run/avahi-daemon.pid
    fi
    
    # Additional cleanup for any stray processes
    echo "Checking for any stray avahi-daemon processes"
    pkill -f avahi-daemon || true
    
    # Clean up any stale socket files
    echo "Removing any stale socket files"
    rm -f /var/run/avahi-daemon/socket
    
    # Ensure the avahi-daemon directory exists with correct permissions
    if [ ! -d /var/run/avahi-daemon ]; then
        echo "Creating /var/run/avahi-daemon directory"
        mkdir -p /var/run/avahi-daemon
    fi
    
    # Set correct ownership for the avahi-daemon directory
    chown -R avahi:avahi /var/run/avahi-daemon
    
    # Double-check that the PID file is gone
    if [ -f /var/run/avahi-daemon/pid ]; then
        echo "PID file still exists after cleanup, forcing removal"
        rm -f /var/run/avahi-daemon/pid
    fi
}

# Function to check if network is ready
wait_for_network() {
    echo "Waiting for network interfaces to be ready..."
    for i in $(seq 1 30); do
        if ip addr show | grep -q "inet "; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Function to start avahi-daemon
start_avahi() {
    echo "Starting avahi-daemon..."
    # Clean up any existing processes first
    cleanup_avahi

    # Wait for network to be ready
    if ! wait_for_network; then
        echo "Network not ready after 30 seconds, starting anyway..."
    fi

    # Run in foreground to capture logs in container logs
    # Removed -D flag to prevent daemonizing, ensuring logs go to stdout/stderr
    # Adding debug flag for more verbose logging
    echo "Starting avahi-daemon in foreground mode..."
    exec avahi-daemon --no-drop-root --no-chroot --no-proc-title --debug

    # Note: The exec command replaces the current process with avahi-daemon
    # This function will not return unless there's an error starting avahi-daemon
    echo "Failed to start avahi-daemon"
    return 1
}

# Main service loop
while true; do
    # Start avahi-daemon in foreground mode
    # If avahi-daemon exits, this loop will restart it
    start_avahi

    # If we get here, avahi-daemon has exited
    echo "avahi-daemon exited, restarting in 5 seconds..."
    sleep 5
done
