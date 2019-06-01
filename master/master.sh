APP_CONFIG_FILE_=./defconfig
APP_LOG_LEVEL_=2
APP_NAME="tekon_master"
APP_LOG_PREFIX_=": TEKON-MASTER"

. ./common.sh
. ./measurements.sh
. ./archives.sh
. ./timesync.sh

usage()
{
  echo "${APP_NAME} [-c config] [-v verbose]"
  echo ""
  echo "  -c - config file"
  echo ""
  echo "  -v - verbose mode"
  echo "       0 - silent"
  echo "       1 - error"
  echo "       2 - warning"
  echo "       3 - info"
  echo "       4 - debug"
  echo ""
  echo "Example"
  echo "  ${APP_NAME} -c /tmp/config -v3"
}

parse_args()
{

  while getopts c:v:h arg
  do
    case $arg in
      c)
        APP_CONFIG_FILE_=$OPTARG
        ;;
      v)
        APP_LOG_LEVEL_=$OPTARG
        ;;
      h)
        usage
        exit 0
        ;;
      \?)
        usage
        exit 1
        ;;
    esac
  done

}

main()
{
  parse_args "$@"

  # Обработчик Ctrl+C
  trap 'exit 1' SIGINT

  # Настройка логов
  log_level "${APP_LOG_LEVEL_}"
  log_info "${APP_LOG_PREFIX_} : config file ${APP_CONFIG_FILE_}"

  # Прочитать настройки
  . "${APP_CONFIG_FILE_}"

  # Проиницилазировать и запустить работы с Тэконами
  local msr
  local arch
  local timesync

  msr_init "$@"
  msr=$?

  arch_init "$@"
  arch=$?

  timesync_init "$@"
  timesync=$?


  if [ ${msr} -ne 0 ] &&  [ ${arch} -ne 0 ] && [ ${timesync} -ne 0 ]; then
    fail "${APP_LOG_PREFIX_} : there is no configured services"
  fi

  while true; do

    if [ ${msr} -eq 0 ]; then
      msr_read
      sleep "${TEKON_SLEEP:-0.25}"
    fi

    if [ ${arch} -eq 0 ]; then
      arch_read
      sleep "${TEKON_SLEEP:-0.25}"
    fi

    if [ ${timesync} -eq 0 ]; then
      timesync_execute
      sleep "${TEKON_SLEEP:-0.25}"
    fi

  done
}

main "$@"
