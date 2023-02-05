#!/bin/sh

WIREGUARD_CONFIG_PATH="${WIREGUARD_CONFIG_PATH-/etc/wireguard/wg0.conf}"

WIREGUARD_HOST="${WIREGUARD_HOST-<WIREGUARD HOST IP>}"

WG_INTERFACE=$(basename "${WIREGUARD_CONFIG_PATH}" .conf)

ip_to_num() {
    IFS="." read -r a b c d <<EOF
$1
EOF
    echo "$((a * 256 * 256 * 256 + b * 256 * 256 + c * 256 + d))"
}

num_to_ip() {
    ip_number="$1"
    delim=""

    for _ in 0 1 2 3; do
        byte=$((ip_number % 256))
        ip_addr="${byte}${delim}${ip_addr}"
        delim="."
        ip_number=$((ip_number / 256))
    done

    echo "${ip_addr}"
}

gen_priv_key() { wg genkey; }
gen_pub_key() { echo "$1" | wg pubkey; }

config_marker_start() { echo "# ======== $1 ========"; }
config_marker_end() { echo "# ===================="; }

config_get_addess() {
    grep -E -i -w "Address" "${WIREGUARD_CONFIG_PATH}" |
        cut -d= -f2 |
        xargs echo
}

config_get_ip() {
    config_get_addess | cut -d/ -f1
}

config_get_subnet() {
    config_get_addess | cut -d/ -f2
}

config_get_network() {
    ip="$(ip_to_num "$(config_get_ip)")"
    subnet="$(config_get_subnet)"

    num_to_ip "$((ip & (~((1 << (32 - subnet)) - 1))))"
}

config_get_peer_count() { grep -c -E -i -w "\[Peer\]" "${WIREGUARD_CONFIG_PATH}"; }

get_next_peer_ip() {
    peer_count="$(config_get_peer_count)"
    ip="$(config_get_ip)"

    address_num="$(ip_to_num "${ip}")"
    peer_num=$((address_num + peer_count + 1))
    peer_ip="$(num_to_ip "${peer_num}")"

    echo "$peer_ip"
}

get_server_pubkey() {
    grep -E -i -w "PrivateKey" "$WIREGUARD_CONFIG_PATH" | cut -d'=' -f2- | xargs echo | wg pubkey
}

config_add_peer() {
    peer_name="$1"
    peer_ip="$2"
    peer_pub_key="$3"

    {
        echo
        config_marker_start "$peer_name"

        echo "[Peer]"
        echo "PublicKey = ${peer_pub_key}"
        echo "AllowedIPs = ${peer_ip}/32"

        config_marker_end
    } >>"$WIREGUARD_CONFIG_PATH"
}

config_reload() {
    wg-quick strip "$WG_INTERFACE" | wg syncconf "$WG_INTERFACE"
}

config_generate_client_tunnel() {
    server_pubkey=$1
    client_privkey=$2
    client_ip=$3
    client_dns=$4
    client_allowed_ips=$5
    client_persistent_keepalive=$6
    wireguard_host=$7

    if [ -z "${client_dns}" ]; then
        dns_line=""
    else
        dns_line="DNS = $client_dns"
    fi

    if [ -z "${client_persistent_keepalive}" ]; then
        persistent_keepalive_line=""
    else
        persistent_keepalive_line="PersistentKeepalive = $6"
    fi

    cat <<EOF
[Interface]
PrivateKey = $client_privkey
Address = $client_ip
$dns_line

[Peer]
PublicKey = $server_pubkey
AllowedIPs = $client_allowed_ips
Endpoint = $wireguard_host
$persistent_keepalive_line
EOF
}

gui_add_user() {
    exec 3>&1

    peer_count="$(config_get_peer_count)"
    peer_name="$(dialog --inputbox "Peer name:" 0 0 "Peer $peer_count" 2>&1 1>&3)"

    wireguard_host="$(dialog --inputbox "Wireguard Host:" 0 0 "$WIREGUARD_HOST" 2>&1 1>&3)"

    peer_ip="$(dialog --inputbox "Peer ip:" 0 0 "$(get_next_peer_ip)" 2>&1 1>&3)"

    peer_dns="$(dialog --inputbox "Peer DNS (defaults to Wireguard Host):" 0 0 "$(config_get_ip)" 2>&1 1>&3)"

    allowed_ips="$(dialog --inputbox "Allowed IPS (defaults to Wireguard network):" 0 0 "$(config_get_network)/$(config_get_subnet)" 2>&1 1>&3)"

    persistent_keepalive="$(dialog --inputbox "Persistent keepalive:" 0 0 "25" 2>&1 1>&3)"

    exec 3>&-

    peer_priv_key=$(gen_priv_key)
    peer_pub_key=$(gen_pub_key "${peer_priv_key}")

    config_add_peer "$peer_name" "$peer_ip" "$peer_pub_key"

    reset

    tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'wg_admin')

    {
        config_generate_client_tunnel "$(get_server_pubkey)" "$peer_priv_key" "$peer_ip" "$peer_dns" "$allowed_ips" "$persistent_keepalive" "$wireguard_host"
    } >"${tmpdir}/${WG_INTERFACE}.conf"

    croc send "${tmpdir}/${WG_INTERFACE}.conf"

    rm -rf "$tmpdir"
}

gui_add_user
