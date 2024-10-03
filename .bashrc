# .bashrc

# Source global definitions
for globalrc in "/etc/bashrc" "/etc/bash.bashrc"; do
	if [ -f $globalrc ]; then
		. $globalrc
	fi
done
unset globalrc

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin" ]]; then
    PATH="$HOME/.local/bin:$PATH"
fi
export PATH

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
	for rc in ~/.bashrc.d/*; do
		if [ -f "$rc" ]; then
			. "$rc"
		fi
	done
	unset rc
fi
