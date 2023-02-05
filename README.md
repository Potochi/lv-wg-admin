# Wireguard Config Generator

Easily add a new peer to your Wireguard configuration.

## Usage
Requires two environment variables to be set:
* WIREGUARD_CONFIG_PATH - path to the wireguard config you want to manage
* WIREGUARD_HOST - ip address or domain where the Wireguard server is located (including the port)

Run
```sh
./lv_wg_newpeer.sh
```