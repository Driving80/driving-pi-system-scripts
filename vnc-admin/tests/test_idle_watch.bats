#!/usr/bin/env bats
# Tests vnc-admin-idle-watch.sh logic by mocking ss + systemctl.

setup() {
    export TMPDIR=$(mktemp -d)
    export VNC_ADMIN_IDLE_MINUTES=1
    export VNC_ADMIN_CHECK_INTERVAL=1
    export VNC_ADMIN_RFB_PORT=59999

    # Mock dir at front of PATH so our fake ss/systemctl/logger get called
    export FAKE_BIN="$TMPDIR/bin"
    mkdir -p "$FAKE_BIN"
    export PATH="$FAKE_BIN:$PATH"

    # Mock ss: returns 0 clients (one header line, no data lines)
    cat > "$FAKE_BIN/ss" <<'EOF'
#!/bin/bash
echo "State   Recv-Q  Send-Q  Local Address:Port  Peer Address:Port  Process"
EOF
    chmod +x "$FAKE_BIN/ss"

    # Mock systemctl: writes invocation to file then exits
    cat > "$FAKE_BIN/systemctl" <<EOF
#!/bin/bash
echo "\$@" >> "$TMPDIR/systemctl.log"
exit 0
EOF
    chmod +x "$FAKE_BIN/systemctl"

    # Mock logger: silent
    cat > "$FAKE_BIN/logger" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$FAKE_BIN/logger"
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "stops service after IDLE_MINUTES with no clients" {
    # With idle=1min, check=1s, the script should call systemctl stop within ~70s
    # We run it under timeout to bound execution
    run timeout 75 bash vnc-admin/pi/vnc-admin-idle-watch.sh
    [ "$status" -eq 0 ]
    [ -f "$TMPDIR/systemctl.log" ]
    grep -q "stop vnc-admin.service" "$TMPDIR/systemctl.log"
}

@test "resets idle counter when clients present" {
    # Mock ss to return 1 client (header + 1 data row)
    cat > "$FAKE_BIN/ss" <<'EOF'
#!/bin/bash
echo "State   Recv-Q  Send-Q  Local Address:Port  Peer Address:Port  Process"
echo "ESTAB   0       0       127.0.0.1:59999     127.0.0.1:54321    users:((\"Xvnc\",pid=1,fd=4))"
EOF
    chmod +x "$FAKE_BIN/ss"

    # Run for 70s, expect NO systemctl call (always 1 client = counter resets)
    run timeout 70 bash vnc-admin/pi/vnc-admin-idle-watch.sh
    # Timeout returns 124 when killed
    [ "$status" -eq 124 ]
    [ ! -f "$TMPDIR/systemctl.log" ] || ! grep -q "stop vnc-admin.service" "$TMPDIR/systemctl.log"
}
