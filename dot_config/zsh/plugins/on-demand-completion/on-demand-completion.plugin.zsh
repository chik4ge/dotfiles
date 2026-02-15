# ref: https://scrapbox.io/elecdeer-pub/zshの補完関数ロードを補完するときまで遅延させる

# 補完を使おうとした時に初めて補完関数を読み込む
# コマンドが存在しない場合は何もしない
# usage: on_demand_completion <command_name> [completion_command]
#   command_name: 補完を行うコマンド名
#   completion_command: 補完を行うコマンド (default: "<command_name> completion zsh")
#   use_eval = true なら eval 実行（デフォルト）、false なら直接コマンド実行
# Example:
#   on_demand_completion 'docker'
#   on_demand_completion 'gh' 'gh completion -s zsh'
on_demand_completion() {
    local cmd_name=$1
    local completion_command="${2:-${cmd_name} completion zsh}"
    local use_eval="${3:-true}"
    local function_name="_${cmd_name}"

    # コマンドが存在するかチェック
    if ! command -v "$cmd_name" &>/dev/null; then
        # echo "Command '$cmd_name' not found. Skipping completion registration."
        return
    fi

    # 一時的な関数を定義
    eval "function $function_name() {
      unfunction '$function_name'
      if [[ ${use_eval} == true ]]; then
        eval \"\$(${completion_command})\"
      else
        ${completion_command}
      fi
      \$_comps[$cmd_name]
    }"

    # compdef に登録
    compdef $function_name $cmd_name
}
