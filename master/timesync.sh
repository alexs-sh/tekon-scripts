#============================================================================== 
# Модуль синхронизации времени
# Записывает время машины в счетчики Тэкон.
#
# Для того, чтобы синхронизация работала корректно, на хосте должны
# быть выполнены настройки часового пояса (timezone). 
# Функции для вызова внешними модулями
# timesync_init - выполняет инициалихацию
# timesync_execute - выполняет синхронизацию
#
# Конфигурация модули выполняется при помощи переменных, которые должен
# определить импортирующий модуль
# TEKON_TIMESYNC - список устройств для синзронизации
# TEKON_WORKDIR - рабочая директория, куда будут сохранены результаты работы
# TEKON_ADDRESS - адрес К-104
# TEKON_TIMEOUT_MS - таймаут ожидания ответа
# TEKON_TIMESYNC_BACKEND - путь к программе, выполняющей синхронизацию Тэкона
#============================================================================== 

TIMESYNC_ADDRESSES_=()      # Адреса даты/времени, которые должны быть записаны
TIMESYNC_PASSWORDS_=()      # Пароли
TIMESYNC_CHECKS_=()         # Список проверок
TIMESYNC_RUN_DIR_=""        # Рабочая директория
TIMESYNC_LAST_RUN=0
TIMESYNC_LOG_PREFIX_=": TEKON-TIMESYNC"

timesync_is_enabled()
{
  # Синхронизация разрешена?
  # 0 - разрешено
  if [  ${#TEKON_TIMESYNC[@]} -le 0 ]; then
    return 1
  fi

  return 0
}


timesync_env_test()
{
  # Проверка окружения 
  # Все необходимые для работы переменные должны быть заданы
  # Возвращает 0, если переменные заданы корректно
  if [  ${#TEKON_TIMESYNC[@]} -le 0 ]; then
    log_err "${TIMESYNC_LOG_PREFIX_} : variable 'TEKON_TIMESYNC' not set"
    return 1
  fi

  if [ -z "${TEKON_WORKDIR}" ]; then
    log_err "${TIMESYNC_LOG_PREFIX_} : variable 'TEKON_WORKDIR' not set"
    return 1
  fi

  if [ -z "${TEKON_ADDRESS}" ]; then
    log_err "${TIMESYNC_LOG_PREFIX_} : variable 'TEKON_ADDRESS' not set"
    return 1
  fi

  if [ -z "${TEKON_TIMEOUT_MS}" ]; then
    log_err "${TIMESYNC_LOG_PREFIX_} : variable 'TEKON_TIMEOUT_MS' not set"
    return 1
  fi

  if [ -z "${TEKON_TIMESYNC_TIMEOUT}" ]; then
    log_err "${TIMESYNC_LOG_PREFIX_} : variable 'TEKON_TIMESYNC_TIMEOUT' not set"
    return 1
  fi

  if [ -z "${TEKON_TIMESYNC_BACKEND}" ]; then
    log_err "${TIMESYNC_LOG_PREFIX_} : variable 'TEKON_TIMESYNC_BACKEND' not set"
    return 1
  fi

  if [ ! -f "${TEKON_TIMESYNC_BACKEND}" ]; then
    log_err "${TIMESYNC_LOG_PREFIX_} : ${TEKON_ARCH_BACKEND} not a file "
    return 1
  fi

  if [ ! -x "${TEKON_TIMESYNC_BACKEND}" ]; then
    log_err "${TIMESYNC_LOG_PREFIX_} : ${TEKON_ARCH_BACKEND} not an executable file "
    return 1
  fi

  return 0
}

timesync_validate()
{
  # Проверить параметры
  datetime=$1
  password=$2
  checks=$3

  echo "${datetime}" | grep -E -i -q '\b[0-9]{1,3}:0x[0-9A-F]{1,4}:0x[0-9A-F]{1,4}\b' 
  result=$?

  if [ $result -ne 0 ]; then
    log_err "${TIMESYNC_LOG_PREFIX_} : invalid datetime parameter '${datetime}'"
    return 1
  fi

  echo "${password}" | grep -E -i -q '\b[0-9]{8}\b'
  result=$?
  if [ $result -ne 0 ]; then
    log_err "${TIMESYNC_LOG_PREFIX_} : invalid password parameter '${password}'"
    return 1
  fi

  echo "${checks}" | grep -E -q 'none|indexes|difference|minutes'
  result=$?
  if [ $result -ne 0 ]; then
    log_err "${TIMESYNC_LOG_PREFIX_} : invalid checks '${checks}'"
    return 1
  fi

}

timesync_add()
{
    datetime=$1
    password=$2
    checks=$3

    local result
    timesync_validate "$datetime" "$password" "$checks"
    result=$?
    if [ $result -ne 0 ]; then
      return 1
    fi

    idx=${#TIMESYNC_ADDRESSES_[@]}
    TIMESYNC_ADDRESSES_[${idx}]="$datetime"
    TIMESYNC_PASSWORDS_[${idx}]="$password"
    TIMESYNC_CHECKS_[${idx}]="$checks"

    return 0
}

timesync_configure()
{

  local num
  local params
  local checks
  local datetime
  local result
  local checks

  for i in "${TEKON_TIMESYNC[@]}"

  do
    params=$(echo "${i}" | tr " " "\n")
    datetime=$(grep "datetime" <<< "${params}" | cut -d"=" -f2)
    password=$(grep "password" <<< "${params}" | cut -d"=" -f2)
    checks=$(echo "${i}" | tr "=" "\n" | grep -E 'none|indexes|difference|minutes')

    timesync_add "${datetime}" "${password}" "${checks}"

    result=$? 
    if [ $result -ne 0 ]; then
      fail "${TIMESYNC_LOG_PREFIX_} : invalid timesync task at '${i}' (task № $num)"
    fi

    num=$((num+1))
  done

}


timesync_init()
{
  log_info "${TIMESYNC_LOG_PREFIX_} : start init"

  # Чтение архивов разрешено? Определяется по наличии переменной в конфиге
  timesync_is_enabled
  result=$?
  if [ $result -ne 0 ]; then
    log_warn "${TIMESYNC_LOG_PREFIX_} : service disabled. Variable 'TEKON_TIMESYNC' not set"
    return 1
  fi

  # Проверить окружение
  timesync_env_test
  result=$?
  if [ $result -ne 0 ]; then
    fail "${TIMESYNC_LOG_PREFIX_} : environment is invalid"
  fi

  TIMESYNC_ADDRESSES_=()      # Адреса даты/времени, которые должны быть записаны
  TIMESYNC_PASSWORDS_=()      # Пароли
  TIMESYNC_CHECKS_=()         # Список проверок
  TIMESYNC_RUN_DIR_="${TEKON_WORKDIR}/timesync-runtime"
  TIMESYNC_LAST_RUN=0
  # Подготовить коренвые директории
  rm -rf "${TIMESYNC_RUN_DIR_}"
  mkdir -p "${TIMESYNC_RUN_DIR_}"

  # Настроить архивы
  timesync_configure

  log_info "${TIMESYNC_LOG_PREFIX_} : temporary storage: ${TIMESYNC_RUN_DIR_}"
  log_info "${TIMESYNC_LOG_PREFIX_} : sync jobs : ${#TEKON_TIMESYNC[*]}"
  log_info "${TIMESYNC_LOG_PREFIX_} : stop init"


}


timesync_execute()
{
  local result
  local i
  local cnt
  local now
  local est

  timesync_is_enabled
  result=$?
  if [ $result -ne 0 ]; then
    fail "${TIMESYNC_LOG_PREFIX_} : attempt to run disabled service"
  fi

  log_debug "${TIMESYNC_LOG_PREFIX_} : last read ${TIMESYNC_LAST_RUN}"

  now=$(date -u +%s)
  est=$((now - TIMESYNC_LAST_RUN))
  est="${est#-}" #хитрованский способ убрать -

  if [ ${est} -lt "${TEKON_TIMESYNC_TIMEOUT}" ]; then
    log_debug "${TIMESYNC_LOG_PREFIX_} : skip time sync ${est} < ${TEKON_TIMESYNC_TIMEOUT}"
    return 0
  fi

  TIMESYNC_LAST_RUN="${now}"
  log_info "${TIMESYNC_LOG_PREFIX_} : start time synchronization"

  cnt=${#TIMESYNC_ADDRESSES_[*]}
  i=0
  while [ ${i} -lt "${cnt}"  ]; do

    ${TEKON_TIMESYNC_BACKEND} -a"${TEKON_ADDRESS}" \
    -t"${TEKON_TIMEOUT_MS}" \
    -d"${TIMESYNC_ADDRESSES_[${i}]}" \
    -p"${TIMESYNC_PASSWORDS_[${i}]}" \
    -c"${TIMESYNC_CHECKS_[${i}]}" \
    > "${TIMESYNC_RUN_DIR_}/last_sync" 2>"${TIMESYNC_RUN_DIR_}/last_error"

    result=$?
    if [ $result -ne 0 ]; then
      log_warn "${TIMESYNC_LOG_PREFIX_} : synchronization error for ${TIMESYNC_ADDRESSES_[${i}]}"
    fi
    i=$((i+1))
  done
  log_info "${TIMESYNC_LOG_PREFIX_} : stop time synchronization"
}
