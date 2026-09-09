# Symlinked as fedora-<rel>-x86_64-mingw.cfg; the release comes from the
# requested root name (mock sets chroot_name before exec'ing this).
import re

_rel = re.fullmatch(r'fedora-(rawhide|\d+)-x86_64-mingw', config_opts['chroot_name']).group(1)

# Stock Fedora config. mock's include() is textual and literal-only, so call
# the resolver directly (same /etc/mock lookup and config_paths tracking).
_paths = set()
exec(include(f'fedora-{_rel}-x86_64.cfg', config_opts['config_path'], _paths))
config_opts['config_paths'] = list(set(config_opts['config_paths']) | _paths)

config_opts['dnf.conf'] += f"""
[copr:copr.fedorainfracloud.org:ebbex:mingw]
name=Copr repo for mingw owned by ebbex
baseurl=https://download.copr.fedorainfracloud.org/results/ebbex/mingw/fedora-{_rel}-$basearch/
type=rpm-md
skip_if_unavailable=True
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/ebbex/mingw/pubkey.gpg
repo_gpgcheck=0
enabled=1
enabled_metadata=1
"""
