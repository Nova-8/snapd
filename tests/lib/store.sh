#!/bin/sh
STORE_CONFIG=/etc/systemd/system/snapd.service.d/store.conf

. $TESTSLIB/systemd.sh

_configure_store_backends(){
    for snap in snapd.service snapd.socket; do
        if systemctl status "$snap"; then
            systemctl stop "$snap"
        fi
    done
    rm -rf $(dirname $STORE_CONFIG) && mkdir -p $(dirname $STORE_CONFIG)
    cat > $STORE_CONFIG <<EOF
[Service]
Environment=SNAPD_DEBUG=1 SNAPD_DEBUG_HTTP=7
Environment=$*
EOF
    systemctl daemon-reload
    systemctl start snapd.socket
}

setup_staging_store(){
    _configure_store_backends "SNAPPY_USE_STAGING_STORE=1"
}

teardown_staging_store(){
    if systemctl status snapd.socket; then
        systemctl stop snapd.socket
    fi
    rm -rf $STORE_CONFIG
    systemctl daemon-reload
    systemctl start snapd.socket
}

init_fake_refreshes(){
    local refreshable_snaps=$1
    local dir=$2

    fakestore_mark=
    if [ "$REMOTE_STORE" = staging ]; then
        fakestore_mark=SNAPPY_USE_STAGING_STORE=1
    fi

    eval "$fakestore_mark fakestore -make-refreshable $refreshable_snaps -dir $dir"
}

setup_fake_store(){
    local top_dir=$1

    mkdir -p $top_dir/asserts
    # debugging
    systemctl status fakestore || true
    echo "Given a controlled store service is up"

    https_proxy=${https_proxy:-}
    http_proxy=${http_proxy:-}

    fakestore_mark=
    if [ "$REMOTE_STORE" = staging ]; then
        fakestore_mark="SNAPPY_USE_STAGING_STORE=1"
    fi

    systemd_create_and_start_unit fakestore "$(which fakestore) -start -dir $top_dir -addr localhost:11028 -https-proxy=${https_proxy} -http-proxy=${http_proxy} -assert-fallback" "SNAPD_DEBUG=1 SNAPD_DEBUG_HTTP=7 $fakestore_mark"

    echo "And snapd is configured to use the controlled store"
    _configure_store_backends "SNAPPY_FORCE_CPI_URL=http://localhost:11028" "SNAPPY_FORCE_SAS_URL=http://localhost:11028 $fakestore_mark"
}

teardown_fake_store(){
    local top_dir=$1
    systemd_stop_and_destroy_unit fakestore

    if [ "$REMOTE_STORE" = "staging" ]; then
        setup_staging_store
    else
        systemctl stop snapd.socket
        rm -rf $STORE_CONFIG $top_dir
        systemctl daemon-reload
        systemctl start snapd.socket
    fi
}
