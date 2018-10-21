#!/bin/bash
XUD_INSTALL_DIR=~/xud
shopt -s expand_aliases
mkdir -p $XUD_INSTALL_DIR
cd $XUD_INSTALL_DIR || exit
echo "Installing go..."
wget https://dl.google.com/go/go1.11.1.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.11.1.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$(go env GOPATH)
export PATH=$PATH:$GOPATH/bin
{
  echo "export PATH=$PATH:/usr/local/go/bin"
  echo "export GOPATH=$(go env GOPATH)"
  echo "export PATH=$PATH:$GOPATH/bin"
} >> ~/.bashrc
go version
go get -u github.com/Masterminds/glide
glide --version
echo "Installing node"
wget -qO- https://raw.githubusercontent.com/creationix/nvm/v0.33.11/install.sh | bash
export NVM_DIR="$HOME/.nvm"
export PATH=$PATH:$GOPATH/bin
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
nvm --version
nvm install v8.12.0
node -v
echo "Installing Python"
sudo apt install -y python
python --version
echo "Installing g++"
sudo apt install -y g++
g++ --version
echo "Installing make"
sudo apt install -y make
make --version
echo "Installing btcd"
git clone https://github.com/btcsuite/btcd "$GOPATH/src/github.com/btcsuite/btcd"
cd "$GOPATH/src/github.com/btcsuite/btcd" || exit
glide install
go install . ./cmd/...
btcd --version
echo "Installing ltcd"
git clone https://github.com/ltcsuite/ltcd "$GOPATH/src/github.com/ltcsuite/ltcd"
cd "$GOPATH/src/github.com/ltcsuite/ltcd" || exit
glide install
go install . ./cmd/...
ltcd --version
echo "Installing lnd"
git clone -b resolver+simnet-ltcd https://github.com/ExchangeUnion/lnd.git "$GOPATH/src/github.com/lightningnetwork/lnd"
cd "$GOPATH/src/github.com/lightningnetwork/lnd" || exit
git checkout 06642fa8a9803b8e122b8f12a350315fe16a4151
make && make install
lnd --version
echo "Installing xud"
git clone https://github.com/ExchangeUnion/xud.git $XUD_INSTALL_DIR
cd $XUD_INSTALL_DIR || exit
git checkout v1.0.0-alpha.1
npm i
npm run compile
alias xud='$XUD_INSTALL_DIR/bin/xud'
echo "alias xud=\"$XUD_INSTALL_DIR/bin/xud\"" >> ~/.bashrc
echo "alias xucli=\"$XUD_INSTALL_DIR/bin/xucli\"" >> ~/.bashrc
xud --version
echo "All dependencies successfully installed."
