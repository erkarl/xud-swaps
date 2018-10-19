# Cross Chain Atomic Swaps Via Lightning Network Payment Channels
In this guide we're going to do cross chain atomic swaps using Lightning Network payment channels using [Exchange Union Deamon](https://github.com/ExchangeUnion/xud). At the end of this guide we'll swap 1 satoshi for 120 litoshis without having to trust the other party. You can read more about the technical process [here](https://github.com/ExchangeUnion/Lightning-Swap-PoC-v2/blob/master/Concept.md).

It is a continuation to the [Lightning BTC/LTC Swap Guide (v2)](https://github.com/ExchangeUnion/Lightning-Swap-PoC-v2). The main difference is that this version uses xud for managing swaps instead of proof of concept [swap-resolver](https://github.com/ExchangeUnion/swap-resolver). We're also using simnet instead of testnet to speed up the process.

This guide assumes a fresh/clean [Ubuntu Server 18.04.1 LTS](https://www.ubuntu.com/download/server) environment.

## Overview
In order to execute swaps we'll need:
* bitcoin full node to verify on chain transactions
* litecoin full node to verify on chain transactions
* payment channel implementation for the respective chains (lightning network deamon in our case)
* xud to manage Exchange A's orders and payment channels
* xud to manage Exchange B's orders and payment channels

## Dependencies
Run install script
```
wget -qO- https://raw.githubusercontent.com/erkarl/xud-swaps/master/install.sh | bash && source ~/.bashrc
```

The script will install the following dependencies:
* [go1.11.1 + glide](https://golang.org/dl/)
* [node.js via nvm](https://github.com/creationix/nvm)
* [python](https://packages.ubuntu.com/bionic/python) (required to build xud)
* [g++](https://packages.ubuntu.com/bionic/g++) (required to build xud)
* [make](https://packages.ubuntu.com/bionic/make) (required to build lnd)
* [btcd](https://github.com/btcsuite/btcd)
* [ltcd](https://github.com/ltcsuite/ltcd/)
* [lnd resolver+simnet-ltcd](https://github.com/ExchangeUnion/lnd/tree/resolver+simnet-ltcd)
* [xud v1.0.0-alpha.1](https://github.com/ExchangeUnion/xud/tree/v1.0.0-alpha.1)

Depending on your environment resources it could take several minutes.

## Configuration
Now that we have our dependencies installed we can get to work on configuring the environment.

### ltcd testnet
ltcd does not currently support simnet so we'll have to sync it against testnet which will take a while.

1. Start ltcd in a dedicated terminal
```
ltcd --testnet --txindex --rpcuser=xu --rpcpass=xu
```

2. Look up the latest block number from some litecoin testnet explorer such as [testnet.litecointools.com](http://testnet.litecointools.com)

3. We can check the progress of our local ltcd with
```
ltcctl --testnet getinfo --rpcuser=xu --rpcpass=xu
```

4. Once the `blocks` value reaches to the one provided by testnet explorer we are synced.

### btcd simnet
The testnet for bitcoin has been very clogged recently. We're going to run btcd in simnet mode in order to speed up the process.

1. Start btcd in a dedicated terminal
```
btcd --simnet --txindex --rpcuser=xu --rpcpass=xu
```

### Exchange A lnd-btc
Let's make a configuration for exchange A's lnd. We'll connect it to the btcd running in simnet mode in order to quickly open a channel with exchange B's lnd.

We'll start with creating an empty directory
```
mkdir -p ~/swaps/exchange-a/lnd-btc
cd ~/swaps/exchange-a/lnd-btc
```

Next up we'll create a configuration file for lnd so that I'll connect to our btcd.
`vim ~/swaps/exchange-a/lnd-btc/lnd.conf`

```
[Application Options]
no-macaroons=true
listen=localhost:10012
rpclisten=localhost:10002
restlisten=localhost:8002
nobootstrap=1
noseedbackup=1
alias=Exchange A BTC on 10002/10012

[Bitcoin]
bitcoin.active=1
bitcoin.simnet=1
bitcoin.node=btcd

[Btcd]
btcd.rpchost=localhost:18556
btcd.rpcuser=xu
btcd.rpcpass=xu
```

We'll also create an alias `start-xa-lnd-btc` so we can easily start the process in the future.
```
echo 'alias start-xa-lnd-btc="lnd --lnddir=~/swaps/exchange-a/lnd-btc"' >> ~/.bashrc
source ~/.bashrc
```

Start exchange A's lnd-btc in a dedicated terminal
```
start-xa-lnd-btc
```

We can now access exchange A's lnd-btc with
```
lncli --lnddir=~/swaps/exchange-a/lnd-btc --network=simnet --no-macaroons --rpcserver=localhost:10002 getinfo
```

Let's also add an alias for that for convenience
```
echo 'alias xa-lnd-btc="lncli --lnddir=~/swaps/exchange-a/lnd-btc --network=simnet --no-macaroons --rpcserver=localhost:10002"' >> ~/.bashrc
source ~/.bashrc
```

We should now be able to access our lnd with
```
$ xa-lnd-btc getinfo
{
    "identity_pubkey": "025da465936c2bf0ce81ab04538db40b8278cc473dbdeca7f59f6ff749cf41c175",
    "alias": "Exchange A BTC on 10002/10012",
    "num_pending_channels": 0,
    "num_active_channels": 0,
    "num_peers": 0,
    "block_height": 0,
    "block_hash": "683e86bd5c6d110d91b94b97137ba6bfe02dbbdb8e3dff722a669b5d69d77af6",
    "synced_to_chain": false,
    "testnet": false,
    "chains": [
        "bitcoin"
    ],
    "uris": [
    ],
    "best_header_timestamp": "1401292357",
    "version": "0.5.0-beta commit=ac8689c634d1fa6eb4c694e11ea0472bfe81e8ea"
}
```

### Exchange B lnd-btc
Analogically to exchange A's lnd-btc we'll also setup exchange B's lnd-btc

Create a new directory for lnd-btc
```
mkdir -p ~/swaps/exchange-b/lnd-btc
cd ~/swaps/exchange-b/lnd-btc
```

`vim ~/swaps/exchange-b/lnd-btc/lnd.conf`
```
[Application Options]
no-macaroons=true
listen=localhost:20012
rpclisten=localhost:20002
restlisten=localhost:9002
nobootstrap=1
noseedbackup=1
alias=Exchange B BTC on 20002/20012

[Bitcoin]
bitcoin.active=1
bitcoin.simnet=1
bitcoin.node=btcd

[Btcd]
btcd.rpchost=localhost:18556
btcd.rpcuser=xu
btcd.rpcpass=xu
```

Create aliases
```
echo 'alias start-xb-lnd-btc="lnd --lnddir=~/swaps/exchange-b/lnd-btc"' >> ~/.bashrc
echo 'alias xb-lnd-btc="lncli --lnddir=~/swaps/exchange-b/lnd-btc --network=simnet --no-macaroons --rpcserver=localhost:20002"' >> ~/.bashrc
source ~/.bashrc
```

Start exchange B's lnd-btc in a dedicated terminal
```
start-xb-lnd-btc
```

Make sure it's working
```
$ xb-lnd-btc getinfo
{
    "identity_pubkey": "038b31de4c84a3149c144be00be55cd6025438b33b550952330c851ae010402284",
    "alias": "Exchange B BTC on 20002/20012",
    "num_pending_channels": 0,
    "num_active_channels": 0,
    "num_peers": 0,
    "block_height": 400,
    "block_hash": "78a18bb33a4dab2108f9b644eed05f142583791955c13360154c09e36a20dd8a",
    "synced_to_chain": true,
    "testnet": false,
    "chains": [
        "bitcoin"
    ],
    "uris": [
    ],
    "best_header_timestamp": "1539621293",
    "version": "0.5.0-beta commit=ac8689c634d1fa6eb4c694e11ea0472bfe81e8ea"
}
```

### Create BTC payment channels
Next up we're going to create a payment channel between exchange A's lnd-btc and exchange B's lnd-btc.

Create a new address to fund the wallet.
```
$ xa-lnd-btc newaddress np2wkh
{
    "address": "ro3dszzdfJBWiNB6dPK8ETxjiGJnCQiNdP"
}
```

Stop the running btcd process and restart it with the new address as mining address.
```
btcd --simnet --txindex --rpcuser=xu --rpcpass=xu --miningaddr=ro3dszzdfJBWiNB6dPK8ETxjiGJnCQiNdP
```

Generate 400 blocks
```
btcctl --simnet --rpcuser=xu --rpcpass=xu generate 400
```

Check that the wallet is funded
```
$ xa-lnd-btc walletbalance
{
    "total_balance": "1505000000000",
    "confirmed_balance": "1505000000000",
    "unconfirmed_balance": "0"
}
```

Get public key from exchange B's lnd-btc
```
XB_BTC_PUBKEY=`xb-lnd-btc getinfo|grep identity_pubkey|cut -d '"' -f 4`
```

Connect xb-lnd-btc as a peer
```
xa-lnd-btc connect $XB_BTC_PUBKEY@127.0.0.1:20012
```

Verify that xa-lnd-btc has xb-lnd-btc as a peer
```
$ xa-lnd-btc listpeers
{
    "peers": [
        {
            "pub_key": "038b31de4c84a3149c144be00be55cd6025438b33b550952330c851ae010402284",
            "address": "127.0.0.1:20012",
            "bytes_sent": "279",
            "bytes_recv": "279",
            "sat_sent": "0",
            "sat_recv": "0",
            "inbound": false,
            "ping_time": "0"
        }
    ]
}
```

Create a payment channel with 8000000 satoshis on both sides
```
xa-lnd-btc openchannel --node_key=$XB_BTC_PUBKEY --local_amt=16000000 --push_amt=8000000
```

Generate 6 blocks to confirm the funding transaction
```
btcctl --simnet --rpcuser=xu --rpcpass=xu generate 6
```

Verify that the channel is active
```
$ xa-lnd-btc listchannels
{
    "channels": [
        {
            "active": true,
            "remote_pubkey": "038b31de4c84a3149c144be00be55cd6025438b33b550952330c851ae010402284",
            "channel_point": "ddec8c267d1d5ff7752ffa73cce6c993220273172457c83eadf644c1367787c3:0",
            "chan_id": "447501232570368",
            "capacity": "16000000",
            "local_balance": "7990950",
            "remote_balance": "8000000",
            "commit_fee": "9050",
            "commit_weight": "724",
            "fee_per_kw": "12500",
            "unsettled_balance": "0",
            "total_satoshis_sent": "0",
            "total_satoshis_received": "0",
            "num_updates": "0",
            "pending_htlcs": [
            ],
            "csv_delay": 1922,
            "private": false
        }
    ]
}
```

Succes. We now have a direct payment channel between our exchanges. Before we can execute swaps we need to go through the same process for the litecoin chain.

### Exchange A lnd-ltc
Due to simnet not being available, yet. We'll connect it to the ltcd running in testnet mode. Compared to simnet, it's more time consuming, but luckily litecoin's testnet is much better than bitcoin's, for now.

We'll start with creating an empty directory
```
mkdir -p ~/swaps/exchange-a/lnd-ltc
cd ~/swaps/exchange-a/lnd-ltc
```

Next up we'll create a configuration file for lnd so that I'll connect to our ltcd.
`vim ~/swaps/exchange-a/lnd-ltc/lnd.conf`

```
[Application Options]
no-macaroons=true
listen=localhost:10011
rpclisten=localhost:10001
restlisten=localhost:8001
nobootstrap=1
noseedbackup=1
alias=Exchange A LTC on 10001/10011

[Litecoin]
litecoin.active=1
litecoin.testnet=1
litecoin.node=ltcd

[Ltcd]
ltcd.rpchost=localhost:19334
ltcd.rpcuser=xu
ltcd.rpcpass=xu
```

We'll also create an alias `start-xa-lnd-ltc` so we can easily start the process in the future.
```
echo 'alias start-xa-lnd-ltc="lnd --lnddir=~/swaps/exchange-a/lnd-ltc"' >> ~/.bashrc
source ~/.bashrc
```

Start exchange A's lnd-ltc in a dedicated terminal
```
start-xa-lnd-ltc
```

We can now access exchange A's lnd-ltc with
```
lncli --lnddir=~/swaps/exchange-a/lnd-ltc --network=testnet --no-macaroons --rpcserver=localhost:10001 getinfo
```

Let's also add an alias for that for convenience
```
echo 'alias xa-lnd-ltc="lncli --lnddir=~/swaps/exchange-a/lnd-ltc --network=testnet --no-macaroons --rpcserver=localhost:10001"' >> ~/.bashrc
source ~/.bashrc
```

We should now be able to access our lnd with
```
$ xa-lnd-ltc getinfo
{
    "identity_pubkey": "0377fcb2a9d6309b27e10d562b5d5ba3215a4999503d5043516b72fed44d09fb9f",
    "alias": "Exchange A LTC on 10001/10011",
    "num_pending_channels": 0,
    "num_active_channels": 0,
    "num_peers": 0,
    "block_height": 580239,
    "block_hash": "863c1ca775790df1f30b985032145293e1259655e531bb95c6b04301dae086f6",
    "synced_to_chain": false,
    "testnet": true,
    "chains": [
        "litecoin"
    ],
    "uris": [
    ],
    "best_header_timestamp": "1493960689",
    "version": "0.5.0-beta commit=ac8689c634d1fa6eb4c694e11ea0472bfe81e8ea"
}
```

Create a new address to fund the wallet.
```
$ xa-lnd-ltc newaddress np2wkh
{
    "address": "2N8HG9dJNf9dTiRH5PXu5KDETu5CYqM73v5"
}
```

Request litcoin testnet coins from some faucet such as [testnet.thrasher.io](http://testnet.thrasher.io) to the address we just created. We can monitor the progress at testnet explorer [chain.so/testnet/ltc](https://chain.so/testnet/ltc).

After 6 confirmations the funds should be visible when querying for walletbalance.

```
$ xa-lnd-ltc walletbalance
{
    "total_balance": "1000000000",
    "confirmed_balance": "1000000000",
    "unconfirmed_balance": "0"
}
```

### Exchange B lnd-ltc
In order to create a payment channel with Exchange A (xa-lnd-ltc) we need to configure and start Exchange B (xb-lnd-ltc).

Create a new directory for exchange-b/lnd-ltc
```
mkdir -p ~/swaps/exchange-b/lnd-ltc
cd ~/swaps/exchange-b/lnd-ltc
```

`vim ~/swaps/exchange-b/lnd-ltc/lnd.conf`
```
[Application Options]
no-macaroons=true
listen=localhost:20011
rpclisten=localhost:20001
restlisten=localhost:9001
nobootstrap=1
noseedbackup=1
alias=Exchange B LTC on 20001/20011

[Litecoin]
litecoin.active=1
litecoin.testnet=1
litecoin.node=ltcd

[Ltcd]
ltcd.rpchost=localhost:19334
ltcd.rpcuser=xu
ltcd.rpcpass=xu
```

Create aliases
```
echo 'alias start-xb-lnd-ltc="lnd --lnddir=~/swaps/exchange-b/lnd-ltc"' >> ~/.bashrc
echo 'alias xb-lnd-ltc="lncli --lnddir=~/swaps/exchange-b/lnd-ltc --network=testnet --no-macaroons --rpcserver=localhost:20001"' >> ~/.bashrc
source ~/.bashrc
```

Start exchange B's lnd-btc in a dedicated terminal
```
start-xb-lnd-ltc
```

Make sure it's working
```
$ xb-lnd-ltc getinfo
{
    "identity_pubkey": "037828e096e718205deed96b5db1b9189d1ceb94e1ff2d741ade54f628a44b5e0d",
    "alias": "Exchange B LTC on 20001/20011",
    "num_pending_channels": 0,
    "num_active_channels": 0,
    "num_peers": 0,
    "block_height": 809554,
    "block_hash": "77a8bb81d5ef5e075bd19072ba7c0a88ef906804738df4fa25135f4e93738767",
    "synced_to_chain": false,
    "testnet": true,
    "chains": [
        "litecoin"
    ],
    "uris": [
    ],
    "best_header_timestamp": "1491858599",
    "version": "0.5.0-beta commit=ac8689c634d1fa6eb4c694e11ea0472bfe81e8ea"
}
```

### Create LTC payment channels
Next up we're going to create a payment channel between exchange A's lnd-ltc and exchange B's lnd-ltc.

In earlier steps we requested testnet litecoins from the faucet. Let's check that the wallet is funded.
```
$ xa-lnd-ltc walletbalance
{
    "total_balance": "1000000000",
    "confirmed_balance": "1000000000",
    "unconfirmed_balance": "0"
}
```

Since we are dealing with testnet lnd needs to catch up with blocks. Make sure `synced We also need to make sure exchange B's lnd-ltc
```
$ xb-lnd-ltc getinfo
{
    "identity_pubkey": "037828e096e718205deed96b5db1b9189d1ceb94e1ff2d741ade54f628a44b5e0d",
    "alias": "Exchange B LTC on 20001/20011",
    "num_pending_channels": 0,
    "num_active_channels": 0,
    "num_peers": 0,
    "block_height": 809556,
    "block_hash": "a4bc331da697bccf883177b15ef0bcb416cb674a740120c1c5bdf968b442c0c9",
    "synced_to_chain": true,
    "testnet": true,
    "chains": [
        "litecoin"
    ],
    "uris": [
    ],
    "best_header_timestamp": "1539904324",
    "version": "0.5.0-beta commit=ac8689c634d1fa6eb4c694e11ea0472bfe81e8ea"
}
```

Get public key from exchange B's lnd-ltc
```
XB_LTC_PUBKEY=`xb-lnd-ltc getinfo|grep identity_pubkey|cut -d '"' -f 4`
```

Connect xb-lnd-ltc as a peer
```
xa-lnd-ltc connect $XB_LTC_PUBKEY@127.0.0.1:20011
```

Verify that xa-lnd-ltc has xb-lnd-ltc as a peer
```
$ xa-lnd-ltc listpeers
{
    "peers": [
        {
            "pub_key": "037828e096e718205deed96b5db1b9189d1ceb94e1ff2d741ade54f628a44b5e0d",
            "address": "127.0.0.1:20011",
            "bytes_sent": "137",
            "bytes_recv": "279",
            "sat_sent": "0",
            "sat_recv": "0",
            "inbound": false,
            "ping_time": "0"
        }
    ]
}
```

Create a payment channel with 8000000 litoshis on both sides.
```
$ xa-lnd-ltc openchannel --node_key=$XB_LTC_PUBKEY --local_amt=16000000 --push_amt=8000000
{
        "funding_txid": "91436e7e5c0dcf27c89d147c7e6d153b046f05b153bb1c52c9b9368ac93ad3bc"
}
```

Monitor the funding transaction on litecoin testnet explorer [testnet.litecointools.com](http://testnet.litecointools.com)

Once there's 3 confirmations we can relatively safely assume the channel is open. Let's verify that it's active.
```
$ xa-lnd-ltc listchannels
{
    "channels": [
        {
            "active": true,
            "remote_pubkey": "037828e096e718205deed96b5db1b9189d1ceb94e1ff2d741ade54f628a44b5e0d",
            "channel_point": "91436e7e5c0dcf27c89d147c7e6d153b046f05b153bb1c52c9b9368ac93ad3bc:0",
            "chan_id": "890120633382404096",
            "capacity": "16000000",
            "local_balance": "7995475",
            "remote_balance": "8000000",
            "commit_fee": "4525",
            "commit_weight": "724",
            "fee_per_kw": "6250",
            "unsettled_balance": "0",
            "total_satoshis_sent": "0",
            "total_satoshis_received": "0",
            "num_updates": "0",
            "pending_htlcs": [
            ],
            "csv_delay": 576,
            "private": false
        }
    ]
}
```
We can now move on to configure xud clients for each exchange.

### Exchange A xud
Exchange A's xud node is responsible for managing payment channels on multiple chains. In our case it's xa-lnd-btc and xa-lnd-ltc.

Create configuration file `vim ~/swaps/exchange-a/xud.conf`. Please note that you'll have to fill in your absolute path for lnd-btc's and lnd-ltc's `certpath`.
```
[rpc]
port = 7001

[webproxy]
disable = true
port = 8080

[db]
username = "xud"
password = ""
database = "exchangeA"
port = 3306
host = "localhost"

[p2p]
listen = true
port = 8885
#make sure this port is reachable from the internet

[lndltc]
disable = false
host = "localhost"
port = 10001
nomacaroons = true
certpath= "/home/<YOUR_USERNAME>/swaps/exchange-a/lnd-ltc/tls.cert"

[lndbtc]
disable = false
host = "localhost"
port = 10002
nomacaroons = true
certpath= "/home/<YOUR_USERNAME>/swaps/exchange-a/lnd-btc/tls.cert"

[raiden]
disable = true
host = "localhost"
port = 5001
```

Since we're using a slightly modified version of lnd to support resolving the payment hash we'll need to add additional configuration file called `resolve.conf`. It's worth noting that it's currently searching for that file in its parent directory.

Create resolve configuration `vim ~/swaps/exchange-a/resolve.conf`
```
TLS=1
serveraddr=localhost:7001
cafile=tls.cert
```

Create alias to start Exchange A's xud and xucli
```
echo 'alias start-xa-xud="xud -x ~/swaps/exchange-a"' >> ~/.bashrc
echo 'alias xa-xucli="xucli -c=/Users/ar/swaps/exchange-a/tls.cert -p=7001"' >> ~/.bashrc
source ~/.bashrc
```

Start xa-xud in a dedicated terminal
```
start-xa-xud
```

Verify that xud is running
```
$ xa-xucli getinfo
{
  "version": "1.0.0-alpha.1",
  "nodePubKey": "026a781606afa85d2b20d4cf4fa1f1cc04b87944300104675d66246f67dcb93617",
  "urisList": [],
  "numPeers": 3,
  "numPairs": 1,
  "orders": {
    "peer": 0,
    "own": 0
  },
  "lndbtc": {
    "error": "",
    "channels": {
      "active": 1,
      "inactive": 0,
      "pending": 0
    },
    "chainsList": [
      "bitcoin"
    ],
    "blockheight": 412,
    "urisList": [],
    "version": "0.5.0-beta commit=ac8689c634d1fa6eb4c694e11ea0472bfe81e8ea",
    "alias": "Exchange A BTC on 10002/10012"
  },
  "lndltc": {
    "error": "",
    "channels": {
      "active": 1,
      "inactive": 0,
      "pending": 0
    },
    "chainsList": [
      "litecoin"
    ],
    "blockheight": 809575,
    "urisList": [],
    "version": "0.5.0-beta commit=ac8689c634d1fa6eb4c694e11ea0472bfe81e8ea",
    "alias": "Exchange A LTC on 10001/10011"
  }
}
```

Let's also check the channel balances from both lnd-btc and lnd-ltc
```
$ xa-xucli channelbalance
{
  "balancesMap": [
    [
      "BTC",
      {
        "balance": 7990950,
        "pendingOpenBalance": 0
      }
    ],
    [
      "LTC",
      {
        "balance": 7995475,
        "pendingOpenBalance": 0
      }
    ]
  ]
}
```

Now that we have xud configured for Exchange A we'll need to setup Exchange B's before we can start our swap.

### Exchange B xud
Exchange B's xud node is responsible for managing payment channels on multiple chains. In our case it's xb-lnd-btc and xb-lnd-ltc.

Create configuration file `vim ~/swaps/exchange-b/xud.conf`.
```
[rpc]
port = 7002

[webproxy]
disable = true
port = 8080

[db]
username = "xud"
password = ""
database = "exchangeA"
port = 3306
host = "localhost"

[p2p]
listen = true
port = 8895
#make sure this port is reachable from the internet

[lndltc]
disable = false
host = "localhost"
port = 20001
nomacaroons = true
certpath= "/home/<YOUR_USERNAME>/swaps/exchange-b/lnd-ltc/tls.cert"

[lndbtc]
disable = false
host = "localhost"
port = 20002
nomacaroons = true
certpath= "/home/<YOUR_USERNAME>/swaps/exchange-b/lnd-btc/tls.cert"

[raiden]
disable = true
host = "localhost"
port = 5001
```

And, `resolve.conf` so that the custom lnds on both chains can communicate with xud. `vim ~/swaps/exchange-b/resolve.conf`
```
TLS=1
serveraddr=localhost:7002
cafile=tls.cert
```

Create alias to start Exchange B's xud and xucli
```
echo 'alias start-xb-xud="xud -x ~/swaps/exchange-b"' >> ~/.bashrc
echo 'alias xb-xucli="xucli -c=/Users/ar/swaps/exchange-b/tls.cert -p=7002"' >> ~/.bashrc
source ~/.bashrc
```

Start xb-xud in a dedicated terminal
```
start-xb-xud
```

Verify that xud is running
```
$ xb-xucli getinfo
{
  "version": "1.0.0-alpha.1",
  "nodePubKey": "02315d8eaeb6f4dfa2d515646e0f2df7e12959180704cdf14f6c83b4ee86d48616",
  "urisList": [],
  "numPeers": 3,
  "numPairs": 1,
  "orders": {
    "peer": 0,
    "own": 0
  },
  "lndbtc": {
    "error": "",
    "channels": {
      "active": 1,
      "inactive": 0,
      "pending": 0
    },
    "chainsList": [
      "bitcoin"
    ],
    "blockheight": 412,
    "urisList": [],
    "version": "0.5.0-beta commit=ac8689c634d1fa6eb4c694e11ea0472bfe81e8ea",
    "alias": "Exchange B BTC on 20002/20012"
  },
  "lndltc": {
    "error": "",
    "channels": {
      "active": 1,
      "inactive": 0,
      "pending": 0
    },
    "chainsList": [
      "litecoin"
    ],
    "blockheight": 809589,
    "urisList": [],
    "version": "0.5.0-beta commit=ac8689c634d1fa6eb4c694e11ea0472bfe81e8ea",
    "alias": "Exchange B LTC on 20001/20011"
  }
}
```

Let's also check the channel balances from both lnd-btc and lnd-ltc
```
$ xb-xucli channelbalance
{
  "balancesMap": [
    [
      "BTC",
      {
        "balance": 8000000,
        "pendingOpenBalance": 0
      }
    ],
    [
      "LTC",
      {
        "balance": 8000000,
        "pendingOpenBalance": 0
      }
    ]
  ]
}
```

We now have 8M SAT/satoshi and 8M LIT/litoshi in Exchange B's channels. Next step is to swap 1 satoshi for 120 litoshis.

## Executing Swaps

Get exchange B's `nodePubKey` so we can connect to it
```
XB_XUD_PUBKEY=`xb-xucli getinfo|grep nodePubKey|cut -d '"' -f 4`
```

Connect exchange A's xud with exchange B's xud.
```
xa-xucli connect $XB_XUD_PUBKEY@127.0.0.1:8895
```

Verify that local peer is connected
```
$ xa-xucli listpeers
{
  "peersList": [
    {
      "address": "xud1.test.exchangeunion.com:8885",
      "nodePubKey": "02b66438730d1fcdf4a4ae5d3d73e847a272f160fee2938e132b52cab0a0d9cfc6",
      "lndBtcPubKey": "02d693d951ce4fc116b2b5e22e8e4966dd3cf9ad7600b8de24190d6af429f260c0",
      "lndLtcPubKey": "0227ee37fbf2035be289206fa7577b03ee9ea6e850953f3767af601dcb1d624087",
      "inbound": false,
      "pairsList": [
        "LTC/BTC",
        "ZRX/GNT"
      ],
      "xudVersion": "1.0.0-prealpha.4",
      "secondsConnected": 5702
    },
    {
      "address": "xud3.test.exchangeunion.com:8885",
      "nodePubKey": "03fd337659e99e628d0487e4f87acf93e353db06f754dccc402f2de1b857a319d0",
      "lndBtcPubKey": "030c2ffd29a92e2dd2fb6fb046b0d9157e0eda8b11caa0e439d0dd6a46a444381c",
      "lndLtcPubKey": "026b4c77e44e602b93b3bcfee0016beeb9063ec3a22795fb233a4f1a90c7b2ffd6",
      "inbound": false,
      "pairsList": [
        "LTC/BTC",
        "ZRX/GNT"
      ],
      "xudVersion": "1.0.0-prealpha.4",
      "secondsConnected": 5702
    },
    {
      "address": "xud2.test.exchangeunion.com:8885",
      "nodePubKey": "028599d05b18c0c3f8028915a17d603416f7276c822b6b2d20e71a3502bd0f9e0a",
      "lndBtcPubKey": "03d6747c9ff24aa8b025027e30556897543642910cbdec066d54f86841ab80966b",
      "lndLtcPubKey": "03df1ac68ffdcbc7e8ee6ac64960e6452da31079b108b228ec13b44fbfefd527c9",
      "inbound": false,
      "pairsList": [
        "LTC/BTC",
        "ZRX/GNT"
      ],
      "xudVersion": "1.0.0-prealpha.4",
      "secondsConnected": 5702
    },
    {
      "address": "127.0.0.1:8895",
      "nodePubKey": "02315d8eaeb6f4dfa2d515646e0f2df7e12959180704cdf14f6c83b4ee86d48616",
      "lndBtcPubKey": "025aa182a87248f6880d8c51e02daf03bb6013f4b079da079538667012be2a45aa",
      "lndLtcPubKey": "037828e096e718205deed96b5db1b9189d1ceb94e1ff2d741ade54f628a44b5e0d",
      "inbound": false,
      "pairsList": [
        "LTC/BTC"
      ],
      "xudVersion": "1.0.0-alpha.1",
      "secondsConnected": 51
    }
  ]
}
```
By default xud also connects to 3 stable test nodes, but we're interested in our local peer `127.0.0.1:8895`.

Check Exchange A's balance
```
$ xa-xucli channelbalance
{
  "balancesMap": [
    [
      "BTC",
      {
        "balance": 7990950,
        "pendingOpenBalance": 0
      }
    ],
    [
      "LTC",
      {
        "balance": 7995475,
        "pendingOpenBalance": 0
      }
    ]
  ]
}
```

Check Exchange B's balance
```
$ xb-xucli channelbalance
{
  "balancesMap": [
    [
      "BTC",
      {
        "balance": 8000000,
        "pendingOpenBalance": 0
      }
    ],
    [
      "LTC",
      {
        "balance": 8000000,
        "pendingOpenBalance": 0
      }
    ]
  ]
}
```

Create a sell order from Exchange A
```
$ xa-xucli sell 0.00000001 LTC/BTC 120
{
  "internalMatchesList": [],
  "swapResultsList": [],
  "remainingOrder": {
    "price": 120,
    "quantity": 1e-8,
    "pairId": "LTC/BTC",
    "id": "bcae3de1-d345-11e8-b7e0-6b99f1faeaa9",
    "peerPubKey": "",
    "localId": "bcae3de0-d345-11e8-b7e0-6b99f1faeaa9",
    "createdAt": 1539915710654,
    "side": 1,
    "isOwnOrder": true
  }
}
```

Create a matching buy order from Exchange B
```
$ xb-xucli buy 0.00000001 LTC/BTC 120
{
  "internalMatchesList": [],
  "swapResultsList": [
    {
      "orderId": "bcae3de1-d345-11e8-b7e0-6b99f1faeaa9",
      "localId": "f1621020-d345-11e8-89ed-6fddd1d1ba13",
      "pairId": "LTC/BTC",
      "quantity": 1e-8,
      "rHash": "5e35d502b0c83373fc87815d08f300a36d5fd1a26953614dd02c787dce955e14",
      "amountReceived": 1,
      "amountSent": 120,
      "peerPubKey": "026a781606afa85d2b20d4cf4fa1f1cc04b87944300104675d66246f67dcb93617",
      "role": 0
    }
  ]
}
```

Looks like our swap succeeded. Let's take a look at the updated channel balances.

Exchange A
```
$ xa-xucli channelbalance
{
  "balancesMap": [
    [
      "BTC",
      {
        "balance": 7990951,
        "pendingOpenBalance": 0
      }
    ],
    [
      "LTC",
      {
        "balance": 7995355,
        "pendingOpenBalance": 0
      }
    ]
  ]
}
```
Exchange A has now +1 SAT and -120 LIT.

Exchange B
```
$ xb-xucli channelbalance
{
  "balancesMap": [
    [
      "BTC",
      {
        "balance": 7999999,
        "pendingOpenBalance": 0
      }
    ],
    [
      "LTC",
      {
        "balance": 8000120,
        "pendingOpenBalance": 0
      }
    ]
  ]
}
```

Success. Exchange B has now -1 SAT and +120 LIT, as intended.
