
export PATH="$HOME/.local/bin:/home/b47m4n/.local/share/mise/installs/node/26.1.0/bin:$PATH"
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
if [[ -f /etc/omarchy.conf ]]; then
  source /etc/omarchy.conf
  export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
else
  export OMARCHY_PATH=/usr/share/omarchy
fi
source "$OMARCHY_PATH/default/bash/rc"

# Load ble.sh
if [[ -f "$HOME/.local/share/blesh/ble.sh" ]]; then
  source "$HOME/.local/share/blesh/ble.sh" --noattach
fi

# History Configuration & Auto-sync across terminal tabs
HISTSIZE=100000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
shopt -s cmdhist
shopt -s checkwinsize
shopt -s globstar 2>/dev/null
PROMPT_COMMAND="history -a; history -n; ${PROMPT_COMMAND:-}"

alias p="python"
alias torch="source ~/torch/bin/activate"
alias f="fastfetch"
alias tf="source ~/tf/bin/activate"
alias kitty-glow="crtty -s ~/.config/crtty/pure_font_glow.glsl"
alias kitty-crt="crtty"

export LD_LIBRARY_PATH=/home/b47m4n/tf/lib/python3.11/site-packages/tensorflow:$LD_LIBRARY_PATH

set -h

export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

if [[ ${BLE_VERSION-} ]]; then
  ble-attach
fi

# Apache Spark Environment Variables
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export SPARK_HOME=/home/b47m4n/opt/spark
export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
