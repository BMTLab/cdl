# Name: cdl.plugin.zsh
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   The file zsh plugin managers look for:
#   oh-my-zsh, zinit, antidote, zplug and the like source it,
#   and it sources cdl.sh from its own directory.
#   %x names the file being sourced,
#   whatever the manager put into $0.

source "${${(%):-%x}:A:h}/cdl.sh"
