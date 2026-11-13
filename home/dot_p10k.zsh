# Archfrican · Powerlevel10k — "rainbow" style with rounded capsules and Nerd Font v3 icons.
# Colors are ANSI indices (0-15), never hex: the prompt follows the palette theme-switch writes to
# ~/.config/ghostty/colors and changes along with the theme. Based on p10k-rainbow.zsh.
# chezmoi manages this file (every Archfrican update rewrites it): to customize, override the
# POWERLEVEL9K_* parameters you want in ~/.zshrc.local — it's sourced after this file, and p10k
# reads its parameters at the first prompt. Apply with `exec zsh`.

'builtin' 'local' '-a' 'p10k_config_opts'
[[ ! -o 'aliases'         ]] || p10k_config_opts+=('aliases')
[[ ! -o 'sh_glob'         ]] || p10k_config_opts+=('sh_glob')
[[ ! -o 'no_brace_expand' ]] || p10k_config_opts+=('no_brace_expand')
'builtin' 'setopt' 'no_aliases' 'no_sh_glob' 'brace_expand'

() {
  emulate -L zsh -o extended_glob
  unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'
  [[ $ZSH_VERSION == (5.<1->*|<6->.*) ]] || return

  typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
    # =========================[ Line #1 ]=========================
    os_icon                 # Arch logo
    dir                     # current directory
    vcs                     # git status
    # =========================[ Line #2 ]=========================
    newline
    prompt_char             # ❯
  )

  typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    # =========================[ Line #1 ]=========================
    status                  # exit code when the command failed
    command_execution_time  # duration when it took >= 3s
    background_jobs         # background jobs
    direnv                  # direnv loaded
    virtualenv              # python venv
    node_version            # node (only inside projects with package.json)
    go_version              # go (only in go projects)
    rust_version            # rust (only in cargo projects)
    context                 # user@host only over SSH or as root
    time                    # clock
    # =========================[ Line #2 ]=========================
    newline
  )

  typeset -g POWERLEVEL9K_MODE=nerdfont-v3
  typeset -g POWERLEVEL9K_ICON_PADDING=none
  typeset -g POWERLEVEL9K_ICON_BEFORE_CONTENT=
  typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true

  # Frame joining the prompt's two lines.
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX='%8F╭─'
  typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_PREFIX='%8F├─'
  typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX='%8F╰─'
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_SUFFIX='%8F─╮'
  typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_SUFFIX='%8F─┤'
  typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_SUFFIX='%8F─╯'
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR=' '
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_BACKGROUND=
  typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_GAP_BACKGROUND=

  # Rounded separators (capsules).
  typeset -g POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR=''
  typeset -g POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR=''
  typeset -g POWERLEVEL9K_LEFT_SEGMENT_SEPARATOR=''
  typeset -g POWERLEVEL9K_RIGHT_SEGMENT_SEPARATOR=''
  typeset -g POWERLEVEL9K_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  typeset -g POWERLEVEL9K_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_EMPTY_LINE_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=

  #################################[ os_icon ]##################################
  typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND=4
  typeset -g POWERLEVEL9K_OS_ICON_BACKGROUND=0

  ################################[ prompt_char ]################################
  typeset -g POWERLEVEL9K_PROMPT_CHAR_BACKGROUND=
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=2
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=1
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='❯'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VICMD_CONTENT_EXPANSION='❮'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIVIS_CONTENT_EXPANSION='V'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIOWR_CONTENT_EXPANSION='▶'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OVERWRITE_STATE=true
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_{LEFT,RIGHT}_WHITESPACE=

  ##################################[ dir ]##################################
  typeset -g POWERLEVEL9K_DIR_BACKGROUND=4
  typeset -g POWERLEVEL9K_DIR_FOREGROUND=0
  typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=0
  typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=0
  typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=true
  typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique
  typeset -g POWERLEVEL9K_SHORTEN_DELIMITER=
  local anchor_files=(
    .git .hg .svn .node-version .python-version .go-version .ruby-version .tool-versions
    .mise.toml .shorten_folder_marker Cargo.toml composer.json go.mod package.json
    pyproject.toml
  )
  typeset -g POWERLEVEL9K_SHORTEN_FOLDER_MARKER="(${(j:|:)anchor_files})"
  typeset -g POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER=false
  typeset -g POWERLEVEL9K_SHORTEN_DIR_LENGTH=1
  typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=80
  typeset -g POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS=40
  typeset -g POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS_PCT=50
  typeset -g POWERLEVEL9K_DIR_HYPERLINK=false
  typeset -g POWERLEVEL9K_DIR_SHOW_WRITABLE=v3

  #####################################[ vcs: git ]######################################
  # Background by repo state.
  typeset -g POWERLEVEL9K_VCS_CLEAN_BACKGROUND=2        # clean → green
  typeset -g POWERLEVEL9K_VCS_UNTRACKED_BACKGROUND=6    # only new files → cyan
  typeset -g POWERLEVEL9K_VCS_MODIFIED_BACKGROUND=3     # changes → yellow
  typeset -g POWERLEVEL9K_VCS_CONFLICTED_BACKGROUND=1   # conflicts → red
  typeset -g POWERLEVEL9K_VCS_LOADING_BACKGROUND=8
  typeset -g POWERLEVEL9K_VCS_{CLEAN,UNTRACKED,MODIFIED,CONFLICTED,LOADING}_FOREGROUND=0

  # Icon at the segment's left: changes with where the remote is hosted.
  typeset -g POWERLEVEL9K_VCS_GIT_ICON=''           # git
  typeset -g POWERLEVEL9K_VCS_GIT_GITHUB_ICON=''    # GitHub
  typeset -g POWERLEVEL9K_VCS_GIT_GITLAB_ICON=''    # GitLab
  typeset -g POWERLEVEL9K_VCS_GIT_BITBUCKET_ICON='' # Bitbucket
  typeset -g POWERLEVEL9K_VCS_GIT_CODEBERG_ICON=''
  typeset -g POWERLEVEL9K_VCS_GIT_GITEA_ICON=''

  # Git formatter. Example:   main   origin/dev  2 1  1   2  3  4
  # VCS_STATUS_* are filled in by gitstatusd:
  # https://github.com/romkatv/gitstatus/blob/master/gitstatus.plugin.zsh
  function my_git_formatter() {
    emulate -L zsh

    if [[ -n $P9K_CONTENT ]]; then
      # "loading" or vcs_info output: VCS_STATUS_* aren't available.
      typeset -g my_git_format=$P9K_CONTENT
      return
    fi

    local i_branch=$''     #  branch
    local i_tag=$''        #  tag
    local i_commit=$''     #  commit (detached HEAD)
    local i_remote=$''     #  remote tracking branch
    local i_behind=$''     #  commits to pull
    local i_ahead=$''      #  commits to push
    local i_synced=$''     #  in sync with the remote
    local i_stash=$''      #  stashes
    local i_action=$''     #  merge/rebase/cherry-pick in progress
    local i_conflict=$''   #  conflicts
    local i_staged=$''     #  staged
    local i_unstaged=$''   #  modified, not staged
    local i_untracked=$''  #  untracked
    local i_wip=$''        #  WIP commit

    # All text is dark on the segment's colored background.
    local fg='%0F' bold='%B' nobold='%b'
    local res

    if [[ -n $VCS_STATUS_LOCAL_BRANCH ]]; then
      local branch=${(V)VCS_STATUS_LOCAL_BRANCH}
      # Branches longer than 32 chars: first 12 … last 12.
      (( $#branch > 32 )) && branch[13,-13]="…"
      res+="${fg}${i_branch} ${bold}${branch//\%/%%}${nobold}"
    fi

    # Tag only when there's no branch (HEAD on a tag).
    if [[ -n $VCS_STATUS_TAG && -z $VCS_STATUS_LOCAL_BRANCH ]]; then
      local tag=${(V)VCS_STATUS_TAG}
      (( $#tag > 32 )) && tag[13,-13]="…"
      res+="${fg}${i_tag} ${bold}${tag//\%/%%}${nobold}"
    fi

    # Commit when there's neither a branch nor a tag.
    [[ -z $VCS_STATUS_LOCAL_BRANCH && -z $VCS_STATUS_TAG ]] &&
      res+="${fg}${i_commit} ${bold}${VCS_STATUS_COMMIT[1,8]}${nobold}"

    # Remote branch only when its name differs from the local one.
    if [[ -n ${VCS_STATUS_REMOTE_BRANCH:#$VCS_STATUS_LOCAL_BRANCH} ]]; then
      res+=" ${fg}${i_remote} ${(V)VCS_STATUS_REMOTE_BRANCH//\%/%%}"
    fi

    if [[ $VCS_STATUS_COMMIT_SUMMARY == (|*[^[:alnum:]])(wip|WIP)(|[^[:alnum:]]*) ]]; then
      res+=" ${fg}${i_wip}wip"
    fi

    if (( VCS_STATUS_COMMITS_AHEAD || VCS_STATUS_COMMITS_BEHIND )); then
      (( VCS_STATUS_COMMITS_BEHIND )) && res+=" ${fg}${i_behind}${VCS_STATUS_COMMITS_BEHIND}"
      (( VCS_STATUS_COMMITS_AHEAD  )) && res+=" ${fg}${i_ahead}${VCS_STATUS_COMMITS_AHEAD}"
    elif [[ -n $VCS_STATUS_REMOTE_BRANCH ]]; then
      res+=" ${fg}${i_synced}"
    fi

    # Push remote that differs from the upstream (triangular workflows).
    (( VCS_STATUS_PUSH_COMMITS_BEHIND )) && res+=" ${fg}⇠${VCS_STATUS_PUSH_COMMITS_BEHIND}"
    (( VCS_STATUS_PUSH_COMMITS_AHEAD  )) && res+=" ${fg}⇢${VCS_STATUS_PUSH_COMMITS_AHEAD}"

    (( VCS_STATUS_STASHES        )) && res+=" ${fg}${i_stash} ${VCS_STATUS_STASHES}"
    [[ -n $VCS_STATUS_ACTION     ]] && res+=" ${fg}${bold}${i_action} ${VCS_STATUS_ACTION}${nobold}"
    (( VCS_STATUS_NUM_CONFLICTED )) && res+=" ${fg}${bold}${i_conflict} ${VCS_STATUS_NUM_CONFLICTED}${nobold}"
    (( VCS_STATUS_NUM_STAGED     )) && res+=" ${fg}${i_staged} ${VCS_STATUS_NUM_STAGED}"
    (( VCS_STATUS_NUM_UNSTAGED   )) && res+=" ${fg}${i_unstaged} ${VCS_STATUS_NUM_UNSTAGED}"
    (( VCS_STATUS_NUM_UNTRACKED  )) && res+=" ${fg}${i_untracked} ${VCS_STATUS_NUM_UNTRACKED}"
    # "─" when the number of changes is unknown (huge index or bash.showDirtyState=false).
    (( VCS_STATUS_HAS_UNSTAGED == -1 )) && res+=" ${fg}─"

    typeset -g my_git_format=$res
  }
  functions -M my_git_formatter 2>/dev/null

  typeset -g POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY=-1
  # Ignore a possible git repo rooted at $HOME.
  typeset -g POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN='~'
  typeset -g POWERLEVEL9K_VCS_DISABLE_GITSTATUS_FORMATTING=true
  typeset -g POWERLEVEL9K_VCS_CONTENT_EXPANSION='${$((my_git_formatter()))+${my_git_format}}'
  typeset -g POWERLEVEL9K_VCS_{STAGED,UNSTAGED,UNTRACKED,CONFLICTED,COMMITS_AHEAD,COMMITS_BEHIND}_MAX_NUM=-1
  typeset -g POWERLEVEL9K_VCS_BACKENDS=(git)

  ##########################[ status ]###########################
  typeset -g POWERLEVEL9K_STATUS_EXTENDED_STATES=true
  typeset -g POWERLEVEL9K_STATUS_OK=false
  typeset -g POWERLEVEL9K_STATUS_OK_PIPE=false
  typeset -g POWERLEVEL9K_STATUS_ERROR=true
  typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND=0
  typeset -g POWERLEVEL9K_STATUS_ERROR_BACKGROUND=1
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL=true
  typeset -g POWERLEVEL9K_STATUS_VERBOSE_SIGNAME=false
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_FOREGROUND=0
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_BACKGROUND=1
  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE=true
  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE_FOREGROUND=0
  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE_BACKGROUND=1

  ###################[ command_execution_time ]###################
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=0
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FORMAT='d h m s'
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=0
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_BACKGROUND=3

  #######################[ background_jobs ]########################
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_VERBOSE=false
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND=0
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_BACKGROUND=6

  #######################[ direnv ]########################
  typeset -g POWERLEVEL9K_DIRENV_FOREGROUND=0
  typeset -g POWERLEVEL9K_DIRENV_BACKGROUND=3

  ################[ virtualenv / node / go / rust ]################
  typeset -g POWERLEVEL9K_VIRTUALENV_FOREGROUND=0
  typeset -g POWERLEVEL9K_VIRTUALENV_BACKGROUND=4
  typeset -g POWERLEVEL9K_VIRTUALENV_SHOW_PYTHON_VERSION=false
  typeset -g POWERLEVEL9K_VIRTUALENV_SHOW_WITH_PYENV=false
  typeset -g POWERLEVEL9K_VIRTUALENV_{LEFT,RIGHT}_DELIMITER=

  typeset -g POWERLEVEL9K_NODE_VERSION_FOREGROUND=0
  typeset -g POWERLEVEL9K_NODE_VERSION_BACKGROUND=2
  typeset -g POWERLEVEL9K_NODE_VERSION_PROJECT_ONLY=true

  typeset -g POWERLEVEL9K_GO_VERSION_FOREGROUND=0
  typeset -g POWERLEVEL9K_GO_VERSION_BACKGROUND=6
  typeset -g POWERLEVEL9K_GO_VERSION_PROJECT_ONLY=true

  typeset -g POWERLEVEL9K_RUST_VERSION_FOREGROUND=0
  typeset -g POWERLEVEL9K_RUST_VERSION_BACKGROUND=5
  typeset -g POWERLEVEL9K_RUST_VERSION_PROJECT_ONLY=true

  ##################################[ context ]##################################
  # user@host hidden locally; shown over SSH (magenta) or as root (red).
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_FOREGROUND=0
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_BACKGROUND=1
  typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_FOREGROUND=0
  typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_BACKGROUND=5
  typeset -g POWERLEVEL9K_CONTEXT_FOREGROUND=0
  typeset -g POWERLEVEL9K_CONTEXT_BACKGROUND=7
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_TEMPLATE='%B%n@%m'
  typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_TEMPLATE='%n@%m'
  typeset -g POWERLEVEL9K_CONTEXT_TEMPLATE='%n@%m'
  typeset -g POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}_{CONTENT,VISUAL_IDENTIFIER}_EXPANSION=

  ####################################[ time ]####################################
  typeset -g POWERLEVEL9K_TIME_FOREGROUND=7
  typeset -g POWERLEVEL9K_TIME_BACKGROUND=0
  typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%H:%M}'
  typeset -g POWERLEVEL9K_TIME_UPDATE_ON_COMMAND=false

  # Past prompts collapse to "❯ command" (except the first one after a directory change),
  # keeping the terminal scrollback clean.
  typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=same-dir
  typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
  typeset -g POWERLEVEL9K_DISABLE_HOT_RELOAD=true

  (( ! $+functions[p10k] )) || p10k reload
}

typeset -g POWERLEVEL9K_CONFIG_FILE=${${(%):-%x}:a}

(( ${#p10k_config_opts} )) && setopt ${p10k_config_opts[@]}
'builtin' 'unset' 'p10k_config_opts'
