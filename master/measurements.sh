#============================================================================== 
# Модуль чтения измерений
# Занимается чтением данных и определением статусов устройств (оналйн/оффлайн)
# и сохранением информации в файлы
#
# Функции для вызова внешними модулями
# msr_init - выполняет инициалихацию
# msr_read - выполняет чтение значений
#
# Конфигурация модули выполняется при помощи переменных, которые должен
# определить импортирующий модуль
# TEKON_TAG - список параметров для чтения
# TEKON_WORKDIR - рабочая директория, куда будут сохранены результаты работы
# (параметры) и пром. данные (статусы)
# TEKON_ADDRESS - адрес К-104
# TEKON_TIMEOUT_MS - таймаут ожидания ответа
# TEKON_MSR_BACKEND - путь к программе, выплняющей чтение с Тэкона 
#============================================================================== 
MSR_TAG_NAME_=()          # Информацтя об именах тэгов

MSR_TAG_DATA_BY_DEV_=()   # Информация о тэгах устройства. Индекс = адрес. Значение = строка с тэгами
MSR_TAG_NAME_BY_DEV_=()   # Информация об именах тэгов устройства Индекс = адрес. Значение = строка с именами тэгов
MSR_TAG_PROBE_BY_DEV_=()  # Пробный тэг для устройства

MSR_DEVICE_LIST_=()       # Список устройств
MSR_DEVICE_STATUS_=()     # Информация о статусе устройства (индекс = адрес)

MSR_DIR_=""
MSR_RUN_DIR_=""
MSR_LOG_PREFIX_=": TEKON-MSR"

msr_is_enabled()
{
  # Чтение измерений разрешено?
  # 0 - разрешено
  if [  ${#TEKON_TAGS[@]} -le 0 ]; then
    return 1
  fi

  return 0
}

msr_env_test()
{
  # Проверка окружения 
  # Все необходимые для работы переменные должны быть заданы
  # Возвращает 0, если переменные заданы корректно
  if [  ${#TEKON_TAGS[@]} -le 0 ]; then
    log_err "${MSR_LOG_PREFIX_} : variable 'TEKON_TAGS' not set"
    return 1
  fi

  if [ -z "${TEKON_WORKDIR}" ]; then
    log_err "${MSR_LOG_PREFIX_} : variable 'TEKON_WORKDIR' not set"
    return 1
  fi

  if [ -z "${TEKON_ADDRESS}" ]; then
    log_err "${MSR_LOG_PREFIX_} : variable 'TEKON_ADDRESS' not set"
    return 1
  fi

  if [ -z "${TEKON_TIMEOUT_MS}" ]; then
    log_err "${MSR_LOG_PREFIX_} : variable 'TEKON_TIMEOUT_MS' not set"
    return 1
  fi

  if [ -z "${TEKON_MSR_BACKEND}" ]; then
    log_err "${MSR_LOG_PREFIX_} : variable 'TEKON_MSR_BACKEND' not set"
    return 1
  fi

  if [ ! -f "${TEKON_MSR_BACKEND}" ]; then
    log_err "${MSR_LOG_PREFIX_} : ${TEKON_MSR_BACKEND} not a file "
    return 1
  fi

  if [ ! -x "${TEKON_MSR_BACKEND}" ]; then
    log_err "${MSR_LOG_PREFIX_} : ${TEKON_MSR_BACKEND} not an executable file "
    return 1
  fi

  return 0
}

msr_tag_validate_uniqueness()
{
  # Проверить уникальность имени тэга
  # Аргументы
  #  - имя
  echo "${MSR_TAG_NAME_[*]}" | grep -q "$1" 
  result=$?
  if [ $result -eq 0 ]; then
    log_err "${MSR_LOG_PREFIX_} : duplicated tag '$1'"
    return 1
  fi

  return 0
}

msr_tag_validate()
{
  # Проверка параметров тэга
  # Аргументы
  #  - адрес
  #  - параметр
  #  - индекс
  #  - тип
  # Возвращает 0, если проверка выполнена успешно

  local device="$1"
  local parameter="$2"
  local index="$3"
  local ttype="$4"

  # Базовые проверки
  # Проверить адрес устройства
  grep -E -q '\b([0-9]{1,2}|[1-2][0-5][0-5])\b' <<< "${device}"
  result=$?
  if [ $result -ne 0 ]; then
    log_err "${MSR_LOG_PREFIX_} : invalid device '${device}'"
    return 1
  fi

  # Проверить адрес параметра (адреса только в 16-ричной форме)
  grep -E -i -q "\b0x([A-F0-9]){1,4}\b" <<< "${parameter}"
  result=$?
  if [ $result -ne 0 ]; then
    log_err "${MSR_LOG_PREFIX_} : invalid parameter '${parameter}'"
    return 1
  fi

  # Проверить индекс 0 - 4444
  grep -E -i -q "\b[0-4]{1,4}\b" <<< "${index}"
  result=$?
  if [ $result -ne 0 ]; then
    log_err "${MSR_LOG_PREFIX_} : invalid index '${index}'"
    return 1
  fi

  # Проверить тип
  grep -E -i -q "\b[FUHBRDT]{1}\b" <<< "${ttype}"
  result=$?
  if [ $result -ne 0 ]; then
    log_err "${MSR_LOG_PREFIX_} : invalid type '${ttype}'"
    return 1
  fi

  return 0
}

msr_tag_add()
{
  # Добавить тэг Тэкона 
  # Аргументы
  #  - имя
  #  - адрес
  #  - параметр
  #  - индекс
  #  - тип
  # Возвращает 0, если тэг добавлен успешно

  local name="$1"
  local device="$2"
  local parameter="$3"
  local index="$4"
  local ttype="$5"

  msr_tag_validate "${device}" "${parameter}" "${index}" "${ttype}"
  result=$?
  if [ $result -ne 0 ]; then
    return 1
  fi

  msr_tag_validate_uniqueness "${name}"
  result=$?
  if [ $result -ne 0 ]; then
    return 1
  fi

  local data=${device}:${parameter}:${index}:${ttype}

  MSR_TAG_NAME_+=("${name}")

  # Связать устройство и имя тэга. Если это первый добавляемый тэг,то
  # так же выполнить инициализацию директорий
  if [ -z "${MSR_TAG_NAME_BY_DEV_[$device]}" ]; then
    MSR_TAG_NAME_BY_DEV_["${device}"]="${name}"
    MSR_DEVICE_LIST_+=("${device}")
    mkdir -p "${MSR_RUN_DIR_}/${device}"
  else
    MSR_TAG_NAME_BY_DEV_[${device}]="${MSR_TAG_NAME_BY_DEV_[${device}]} ${name}"
  fi

  # Связать устройство и информацию о тэге
  if [ -z "${MSR_TAG_DATA_BY_DEV_[$device]}" ]; then
    MSR_TAG_DATA_BY_DEV_[${device}]="${data}"
  else
    MSR_TAG_DATA_BY_DEV_[${device}]="${MSR_TAG_DATA_BY_DEV_[${device}]} ${data}"
  fi

  # Пробные тэги для девайса. Для каждого девайса выбирается первый тэг из конфиги
  if [ -z "${MSR_TAG_PROBE_BY_DEV_[${device}]}" ]; then
    MSR_TAG_PROBE_BY_DEV_[$device]="${data}"
  fi

  # Если имя тэга содержит директорию+имя файла, то директорию следует создать
  local name_prefix=${name%/*}
  if [ "${name}" != "${name_prefix}" ]; then
    mkdir -p "${MSR_DIR_}/${name_prefix}"
  fi

  echo "${name}" >> "${MSR_RUN_DIR_}/${device}/names"
  echo "${data}" >> "${MSR_RUN_DIR_}/${device}/tags"

}

msr_tag_configure()
{

  local tagnum=1
  local tags=0
  local name=0
  local tekon=0
  local device=0
  local parameter=0
  local index=0
  local ttype=0


  for i in "${TEKON_TAGS[@]}"

  do
    tags=$(echo "${i}" | tr " " "\n")
    name=$(grep "name" <<< "${tags}" | cut -d"=" -f2)
    tekon=$(grep "tekon" <<< "${tags}" | cut -d"=" -f2)
    device=$(echo "$tekon" | cut -d ":" -f1)
    parameter=$(echo "$tekon" | cut -d ":" -f2)
    index=$(echo "$tekon" | cut -d ":" -f3)
    ttype=$(echo "$tekon" | cut -d ":" -f4)

    msr_tag_add "${name}" "${device}" "${parameter}" "${index}" "${ttype}"
    result=$?
    if [ $result -ne 0 ]; then
      fail "${MSR_LOG_PREFIX_} : invalid tag at '${i}' (tag № $tagnum)"
    fi

    tagnum=$((tagnum+1))
  done

}

msr_device_set_status()
{
  # Задачть статус устройства
  # $1 - адрес
  # $2 - статус
  # Возвращает 0, если новые статус установлен
  # Вернет 1, если статус уже был установлен
  local device=$1
  local status=$2

  if [ "${MSR_DEVICE_STATUS_[${device}]}" != "${status}" ]; then
    MSR_DEVICE_STATUS_[${device}]=$status
    echo "$status" > "${MSR_RUN_DIR_}/${device}/status"
    log_info "${MSR_LOG_PREFIX_} : device ${device} set status '${status}'"
    return 0
  fi

  return 1
}

msr_device_probe()
{
  # Проверить наличие связи с устройством
  # $1 - адрес устройства
  # Проверка выполняется при помощ считывания 1 тэга. Если его качество не OK,
  # то проверка считается проваленной
  local device=$1
  local probe="${MSR_RUN_DIR_}/${device}/probe"
  local tag="${MSR_TAG_PROBE_BY_DEV_[${device}]}"
  local run_dir="${MSR_RUN_DIR_}/${device}"

  log_info "${MSR_LOG_PREFIX_} : device ${device} run probe for '${tag}'"

  ${TEKON_MSR_BACKEND} -a"${TEKON_ADDRESS}" -t"${TEKON_TIMEOUT_MS}" -p"${tag}" > "${probe}" 2>"${run_dir}/last_error"

  local result=$?

  # чтение выполнено успешно и качество тэга - OK
  if [ $result -eq 0 ]; then
    #cat "${probe}" | cut -f 4 -d " " | grep "OK" > /dev/null
    cut -f 4 -d " " < "${probe}" | grep "OK" > /dev/null
    result=$?
    if [ $result -eq 0 ]; then
      return 0
    fi
  fi

  # Либо чтение не прошло, либо качество тэга не ОК
  if [ ${result} -ne 0 ]; then
    log_warn "${MSR_LOG_PREFIX_} : device ${device} probe error [${run_dir}/last_error]"
  else
    log_warn "${MSR_LOG_PREFIX_} : device ${device} probe error. Tag '${tag}' is invalid"
  fi

  return 1

}

msr_device_read()
{
  # Прочитать измерения с одного устройства
  # $1 - адрес устройства

  local device=$1
  local run_dir="${MSR_RUN_DIR_}/${device}"
  local tags=${MSR_TAG_DATA_BY_DEV_[${device}]}
  local idx=0
  local name=()
  log_info "${MSR_LOG_PREFIX_} : device ${device} run measurements reading"

  # Прочитать
  ${TEKON_MSR_BACKEND} -a"${TEKON_ADDRESS}" -t"${TEKON_TIMEOUT_MS}" -p"${tags[*]}" > "${run_dir}/last_msr" 2>"${run_dir}/last_error"

  result=$?
  if [ $result -ne 0 ]; then
    log_warn "${MSR_LOG_PREFIX_} : device ${device} read error [${run_dir}/last_error]"
    sleep 1 # Если Тэкон не ответил за нужный таймаут, это еще не значит, что он
    # не ответит чуть позже. Лучше немного выждать
  fi

  # Перенести тэги из временного файла
  idx=0
  read -r -a name <<< "${MSR_TAG_NAME_BY_DEV_[${device}]}"
  while read -r param ttype value qual tstamp tz
  do
    log_debug "${MSR_LOG_PREFIX_} : $param $ttype $value $qual $tstamp $tz"
    echo "$param $ttype $value $qual $tstamp $tz" > "$MSR_DIR_/${name[$idx]}"
    idx=$((idx+1))
  done < "${run_dir}/last_msr"

  log_info "${MSR_LOG_PREFIX_} : device ${device} $idx measurement(s) processed"
}

msr_device_reset()
{
  # Сбросить измерения устройства. Сброс выполняется так же, как и чтение, но с нереальным таймаутом.
  # Тогда утилита чтения просто выведет все тэги с недостоверным качеством и дефолтными значениями
  # $1 - адрес устройства

  local device=$1
  local run_dir="${MSR_RUN_DIR_}/${device}"
  local tags=${MSR_TAG_DATA_BY_DEV_[${device}]}

  # Прочитать
  ${TEKON_MSR_BACKEND} -a"${TEKON_ADDRESS}" -t1 -p"${tags[*]}" > "${run_dir}/last_msr" 2>/dev/null

  # Перенести тэги из временного файла
  local idx=0
  local name=()

  read -r -a name <<< "${MSR_TAG_NAME_BY_DEV_[${device}]}"
  while read -r param ttype value qual tstamp tz
  do
    echo "$param $ttype $value $qual $tstamp $tz" > "$MSR_DIR_/${name[$idx]}"
    idx=$((idx+1))
  done < "${run_dir}/last_msr"
  log_info "${MSR_LOG_PREFIX_} : device ${device} $idx measurement(s) reset"
}

msr_read()
{
  msr_is_enabled
  result=$?
  if [ $result -ne 0 ]; then
    fail "${MSR_LOG_PREFIX_} : attempt to run disabled service"
  fi

  log_info "${MSR_LOG_PREFIX_} : start measurements reading"
  local update=0
  local probe=0
  for dev in "${MSR_DEVICE_LIST_[@]}"; do

    # Выполнить пробное чтение и обновить статусы
    msr_device_probe "${dev}"
    probe=$?
    if [ ${probe} -eq 0 ]; then
      msr_device_set_status "${dev}" "1"
      update=$?
    else
      msr_device_set_status "${dev}" "0"
      update=$?
    fi

    # Если проба выполнена успешно, то прочитать значения
    # Если проба провалена и статус обновлен на FAIL, то 
    # сбросить значения
    if [ ${probe} -eq 0 ]; then
      msr_device_read "$dev"
    else 
      if [ ${update} -eq 0 ]; then
        msr_device_reset "$dev"
        sleep 1
      fi
    fi


  done

  log_info "${MSR_LOG_PREFIX_} : stop measurements reading"

}

msr_init()
{

  log_info "${MSR_LOG_PREFIX_} : start init"

  msr_is_enabled
  result=$?
  if [ $result -ne 0 ]; then
    log_warn "${MSR_LOG_PREFIX_} : service disabled. Variable 'TEKON_TAGS' not set"
    return 1
  fi

  # Проверить окружение
  msr_env_test
  result=$?
  if [ $result -ne 0 ]; then
    fail "${MSR_LOG_PREFIX_} : environment is invalid"
  fi

  # Очистить переменные
  MSR_TAG_NAME_=()
  MSR_DEVICE_LIST_=()
  MSR_DEVICE_STATUS_=()

  MSR_DIR_="${TEKON_WORKDIR}/msr"
  MSR_RUN_DIR_="${TEKON_WORKDIR}/msr-runtime"

  MSR_TAG_DATA_BY_DEV_=()
  MSR_TAG_NAME_BY_DEV_=()
  MSR_TAG_PROBE_BY_DEV_=()

  # Подготовить коренвые директории
  rm -rf "${MSR_DIR_}"
  rm -rf "${MSR_RUN_DIR_}"

  mkdir -p "${MSR_DIR_}"
  mkdir -p "${MSR_RUN_DIR_}"

  # Настроить тэги
  msr_tag_configure

  # Создать директории устройств (runtime)
  for dev in "${MSR_DEVICE_LIST_[@]}"; do
    mkdir -p "${MSR_RUN_DIR_}/${dev}"
  done

  log_info "${MSR_LOG_PREFIX_} : measurments storage: ${MSR_DIR_}"
  log_info "${MSR_LOG_PREFIX_} : temporary storage: ${MSR_RUN_DIR_}"
  log_info "${MSR_LOG_PREFIX_} : devices: ${#MSR_DEVICE_LIST_[*]}"
  log_info "${MSR_LOG_PREFIX_} : tags:${#MSR_TAG_NAME_[*]}"
  log_info "${MSR_LOG_PREFIX_} : stop init"

}

