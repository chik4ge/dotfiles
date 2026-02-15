_pyrunbox_usage() {
  print "pyrunbox: run Python in disposable Docker sandbox"
  print ""
  print "Usage:"
  print "  pyrunbox [options] [--] [python args...]"
  print ""
  print "Options:"
  print "  --network           Enable container network (use host network)"
  print "  --with <package>    Add package via uv (repeatable)"
  print "  --mount <src:dst>   Extra bind mount as read-only (repeatable)"
  print "  --mount-rw <src:dst> Extra bind mount as read-write (repeatable)"
  print "  --python <version>  Python version (3.12, 3.13, 3.14; default: 3.14)"
  print "  -c <code>           Inline Python code"
  print "  -h, --help          Show this help"
}

_pyrunbox_cleanup() {
  local cidfile="$1"

  if [[ -f "$cidfile" ]]; then
    local cid
    cid="$(<"$cidfile")"
    if [[ -n "$cid" ]]; then
      command docker stop -t 2 "$cid" >/dev/null 2>&1 || command docker kill "$cid" >/dev/null 2>&1 || true
    fi
  fi
}

pyrunbox() {
  setopt localoptions localtraps nomonitor

  local python_version="3.14"
  local image="ghcr.io/astral-sh/uv:python3.14-bookworm"
  local network_mode="none"
  local inline_code=""
  local pids_limit="${PYRUNBOX_PIDS_LIMIT:-256}"
  local memory_limit="${PYRUNBOX_MEMORY_LIMIT:-1g}"
  local cpus_limit="${PYRUNBOX_CPUS_LIMIT:-1}"

  local -a with_packages=()
  local -a extra_mounts=()
  local -a python_args=()
  local -a docker_args=()
  local -a warmup_docker_args=()
  local -a uv_args=(run --no-project)
  local -a uv_exec_args=()
  local system_ca_bundle="/etc/ssl/certs/ca-certificates.crt"
  local host_cache_dir="${PYRUNBOX_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pyrunbox/uv}"
  local ciddir=""
  local cidfile=""
  local run_pid=""
  local interrupted=0
  local warmup_status=0
  local exit_status=0

  while (( $# > 0 )); do
    case "$1" in
      --network)
        network_mode="host"
        shift
        ;;
      --python)
        if (( $# < 2 )); then
          print -u2 "pyrunbox: --python requires a version"
          return 2
        fi
        case "$2" in
          3.12|3.13|3.14)
            python_version="$2"
            image="ghcr.io/astral-sh/uv:python${python_version}-bookworm"
            ;;
          *)
            print -u2 "pyrunbox: unsupported --python version '$2' (allowed: 3.12, 3.13, 3.14)"
            return 2
            ;;
        esac
        shift 2
        ;;
      --with)
        if (( $# < 2 )); then
          print -u2 "pyrunbox: --with requires a package name"
          return 2
        fi
        with_packages+=("$2")
        shift 2
        ;;
      --mount|--mount-rw)
        if (( $# < 2 )); then
          print -u2 "pyrunbox: $1 requires <src:dst>"
          return 2
        fi

        local mount_mode="ro"
        if [[ "$1" == "--mount-rw" ]]; then
          mount_mode="rw"
        fi

        local spec="$2"
        local src="${spec%%:*}"
        local dst="${spec#*:}"

        if [[ "$spec" == "$src" || -z "$src" || -z "$dst" ]]; then
          print -u2 "pyrunbox: invalid mount spec '$spec' (expected <src:dst>)"
          return 2
        fi

        if [[ "$src" != /* ]]; then
          src="$PWD/$src"
        fi

        if [[ ! -e "$src" ]]; then
          print -u2 "pyrunbox: mount source not found: $src"
          return 2
        fi

        extra_mounts+=("$src:$dst:$mount_mode")
        shift 2
        ;;
      -c)
        if (( $# < 2 )); then
          print -u2 "pyrunbox: -c requires code"
          return 2
        fi
        inline_code="$2"
        shift 2
        ;;
      -h|--help)
        _pyrunbox_usage
        return 0
        ;;
      --)
        shift
        python_args+=("$@")
        break
        ;;
      *)
        python_args+=("$1")
        shift
        ;;
    esac
  done

  local pkg
  for pkg in "${with_packages[@]}"; do
    uv_args+=(--with "$pkg")
  done

  if [[ -n "$inline_code" ]]; then
    python_args=(-c "$inline_code" "${python_args[@]}")
  fi

  if (( ${#python_args[@]} == 0 )) && [[ ! -t 0 ]]; then
    python_args=(-)
  fi

  command mkdir -p "$host_cache_dir" || {
    print -u2 "pyrunbox: failed to prepare cache directory: $host_cache_dir"
    return 1
  }

  docker_args+=(
    --rm --init
    --cap-drop ALL
    --security-opt no-new-privileges
    --pids-limit "$pids_limit"
    --memory "$memory_limit"
    --cpus "$cpus_limit"
    --workdir /work
    --network "$network_mode"
    -v "$PWD:/work"
    -v "$host_cache_dir:/root/.cache/uv"
  )

  warmup_docker_args+=(
    --rm --init
    --cap-drop ALL
    --security-opt no-new-privileges
    --pids-limit "$pids_limit"
    --memory "$memory_limit"
    --cpus "$cpus_limit"
    --workdir /work
    --network host
    -v "$PWD:/work"
    -v "$host_cache_dir:/root/.cache/uv"
  )

  if [[ "$network_mode" != "none" ]]; then
    docker_args+=(-e "SSL_CERT_FILE=${SSL_CERT_FILE:-$system_ca_bundle}")
    docker_args+=(-e "REQUESTS_CA_BUNDLE=${REQUESTS_CA_BUNDLE:-$system_ca_bundle}")
  fi

  warmup_docker_args+=(-e "SSL_CERT_FILE=${SSL_CERT_FILE:-$system_ca_bundle}")
  warmup_docker_args+=(-e "REQUESTS_CA_BUNDLE=${REQUESTS_CA_BUNDLE:-$system_ca_bundle}")

  local m
  for m in "${extra_mounts[@]}"; do
    docker_args+=(-v "$m")
    warmup_docker_args+=(-v "$m")
  done

  if [[ -z "$inline_code" ]]; then
    docker_args+=(-i)
  fi

  uv_exec_args=("${uv_args[@]}")

  if [[ "$network_mode" == "none" && ${#with_packages[@]} -gt 0 ]]; then
    trap 'interrupted=1; _pyrunbox_cleanup "$cidfile"; [[ -n "$run_pid" ]] && kill -TERM "$run_pid" >/dev/null 2>&1 || true' INT TERM

    ciddir="$(mktemp -d "${TMPDIR:-/tmp}/pyrunbox.cid.XXXXXX")" || {
      print -u2 "pyrunbox: failed to create temporary directory"
      return 1
    }
    cidfile="$ciddir/cid"

    command docker run --cidfile "$cidfile" "${warmup_docker_args[@]}" "$image" uv "${uv_args[@]}" python -c "pass" &
    run_pid=$!
    wait "$run_pid"
    warmup_status=$?
    run_pid=""

    if (( interrupted )); then
      warmup_status=130
    fi

    _pyrunbox_cleanup "$cidfile"
    rm -rf "$ciddir"
    cidfile=""
    ciddir=""

    if (( warmup_status != 0 )); then
      trap - INT TERM
      return "$warmup_status"
    fi

    uv_exec_args+=(--offline)
  fi

  ciddir="$(mktemp -d "${TMPDIR:-/tmp}/pyrunbox.cid.XXXXXX")" || {
    print -u2 "pyrunbox: failed to create temporary directory"
    return 1
  }
  cidfile="$ciddir/cid"

  trap 'interrupted=1; _pyrunbox_cleanup "$cidfile"; [[ -n "$run_pid" ]] && kill -TERM "$run_pid" >/dev/null 2>&1 || true' INT TERM

  command docker run --cidfile "$cidfile" "${docker_args[@]}" "$image" uv "${uv_exec_args[@]}" python "${python_args[@]}" &
  run_pid=$!
  wait "$run_pid"
  exit_status=$?

  if (( interrupted )); then
    exit_status=130
  fi

  trap - INT TERM
  _pyrunbox_cleanup "$cidfile"
  rm -rf "$ciddir"

  return "$exit_status"
}
