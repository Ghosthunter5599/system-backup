export PATH="/home/b47m4n/.local/share/mise/installs/node/26.1.0/bin:$PATH"
export LD_LIBRARY_PATH=$(python -c "import tensorflow as tf; print(tf.__file__.rsplit(\"/\",1)[0])"):$LD_LIBRARY_PATH
