# MESA cloud shell prompt — colors match the /etc/motd landing screen
# (green user, muted @, cyan host, muted path, orange $>). Sourced from
# ~/.bashrc and /etc/profile.d/. Interactive shells only.
case "$-" in
  *i*)
    PS1='\[\e[38;2;74;222;128m\]${IPLANT_USER:-\u}\[\e[38;2;74;98;114m\]@\[\e[38;2;45;212;191m\]mesa\[\e[0m\] \[\e[38;2;74;98;114m\]\w\[\e[0m\] \[\e[38;2;212;113;42m\]$>\[\e[0m\] '
    ;;
esac
