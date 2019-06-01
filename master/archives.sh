#============================================================================== 
# Модуль чтения архивов
# Занимается чтением архивов и сохранением их в файлы.
# Чтение имеет особенности. При первом проходе по архивам, каждый вызов arch_read 
# приводит к чтения архива. Все послежующте проходы - выполняется контроль
# таймаута. Если таймаут не истек то чтение пропускается. 
# Это позволяется довольно быстро получить архивы после старта скрипта, а затем 
# не тратить лишнее время на постоянное перечитывание
#
# Функции для вызова внешними модулями
# arch_init - выполняет инициалихацию
# arch_read - выполняет чтение
#
# Конфигурация модули выполняется при помощи переменных, которые должен
# определить импортирующий модуль
# TEKON_ARCH - список архивов для чтения
# TEKON_WORKDIR - рабочая директория, куда будут сохранены результаты работы
# (архивы) и пром. данные 
# TEKON_ADDRESS - адрес К-104
# TEKON_TIMEOUT_MS - таймаут ожидания ответа
# TEKON_ARCH_BACKEND - путь к прошрамму, выполняющей чтение с Тэкона
#============================================================================== 

ARCH_NAME_=()         #Информация об именах архивов
ARCH_PARAM_=()        #Информация об адресах архивов
ARCH_INTERVAL_=()     #Информация об интервалах архивов
ARCH_DATETIME_=()     #Информация об дате/времени архивов

ARCH_LAST_READ_=0
ARCH_INIT_DONE_=0     #Инициализация окончена - первый цикл по всем архивам пройдет
ARCH_CURRENT_=0

ARCH_DIR_=""
ARCH_RUN_DIR_=""
ARCH_LOG_PREFIX_=": TEKON-ARCH"

arch_is_enabled()
{
  # Чтение измерений разрешено?
  # 0 - разрешено
  if [  ${#TEKON_ARCH[@]} -le 0 ]; then
    return 1
  fi

  return 0
}

arch_env_test()
{
  # Проверка окружения 
  # Все необходимые для работы переменные должны быть заданы
  # Возвращает 0, если переменные заданы корректно
  if [  ${#TEKON_ARCH[@]} -le 0 ]; then
    log_err "${ARCH_LOG_PREFIX_} : variable 'TEKON_ARCH' not set"
    return 1
  fi

  if [ -z "${TEKON_WORKDIR}" ]; then
    log_err "${ARCH_LOG_PREFIX_} : variable 'TEKON_WORKDIR' not set"
    return 1
  fi

  if [ -z "${TEKON_ADDRESS}" ]; then
    log_err "${ARCH_LOG_PREFIX_} : variable 'TEKON_ADDRESS' not set"
    return 1
  fi

  if [ -z "${TEKON_TIMEOUT_MS}" ]; then
    log_err "${ARCH_LOG_PREFIX_} : variable 'TEKON_TIMEOUT_MS' not set"
    return 1
  fi

  if [ -z "${TEKON_ARCH_BACKEND}" ]; then
    log_err "${ARCH_LOG_PREFIX_} : variable 'TEKON_ARCH_BACKEND' not set"
    return 1
  fi

  if [ ! -f "${TEKON_ARCH_BACKEND}" ]; then
    log_err "${ARCH_LOG_PREFIX_} : ${TEKON_ARCH_BACKEND} not a file "
    return 1
  fi

  if [ ! -x "${TEKON_ARCH_BACKEND}" ]; then
    log_err "${ARCH_LOG_PREFIX_} : ${TEKON_ARCH_BACKEND} not an executable file "
    return 1
  fi

  return 0
}

arch_validate_uniqueness()
{
  # Проверить уникальность имени тэга
  # Аргументы
  #  - имя
  echo "${ARCH_NAME_[*]}" | grep -q "$1" 
  result=$?
  if [ $result -eq 0 ]; then
    log_err "${ARCH_LOG_PREFIX_} : duplicated tag '$1'"
    return 1
  fi

  return 0
}


arch_validate()
{
  # Проверка параметров тэга
  # Аргументы
  #  - параметр
  #  - интервал
  #  - адрес даты/времени
  # Возвращает 0, если проверка выполнена успешно

  local parameter
  local interval
  local datetime

  parameter="$1"
  interval="$2"
  datetime="$3"

  # Базовые проверки
  # Проверить параметр архива parameter=3:8017:0:1536:F
  grep -E -q -i "\b([0-9]{1,2}|[1-2][0-5][0-5]):0x[a-f0-9]{1,4}:[0-9]{1,4}:[0-9]{1,4}:[FUHBR]\b" <<< "${parameter}"
  result=$?
  if [ $result -ne 0 ]; then
    log_err "${ARCH_LOG_PREFIX_} : invalid parameter '${parameter}'"
    return 1
  fi

  # Проверить интервал
  grep -E -i -q "\bm:[0-9]{2}|h:[0-9]{3,4}|d:36[56]|i:[0-9]{1,4}:[0-9]{1}" <<< "${interval}"
  result=$?
  if [ $result -ne 0 ]; then
    log_err "${ARCH_LOG_PREFIX_} : invalid interval '${interval}'"
    return 1
  fi

  # Проверить адрес даты/времени
  grep -E -i -q "\b([0-9]{1,2}|[1-2][0-5][0-5]):0x[a-f0-9]{1,4}:0x[a-f0-9]{1,4}\b" <<< "${datetime}"
  result=$?
  if [ $result -ne 0 ]; then
    log_err "${ARCH_LOG_PREFIX_} : invalid datetime '${datetime}'"
    return 1
  fi

  return 0
}

arch_add()
{
  # Добавить тэг Тэкона 
  # Аргументы
  #  - имя
  #  - параметр
  #  - интервал
  #  - адрес даты/времени
  # Возвращает 0, если архив добавлен успешно

  local name
  local parameter
  local interval
  local datetime
  local idx
  local name_prefix

  name=$1
  parameter=$2
  interval=$3
  datetime=$4

  arch_validate "${parameter}" "${interval}" "${datetime}"
  result=$?
  if [ $result -ne 0 ]; then
    return 1
  fi

  arch_validate_uniqueness "${name}"
  result=$?
  if [ $result -ne 0 ]; then
    return 1
  fi

  idx=${#ARCH_NAME_[@]}

  ARCH_NAME_[${idx}]="${name}"
  ARCH_PARAM_[${idx}]="${parameter}"
  ARCH_INTERVAL_[${idx}]="${interval}"
  ARCH_DATETIME_[${idx}]="${datetime}"

  # Если имя тэга содержит директорию+имя файла, то директорию следует создать
  name_prefix=${name%/*}
  if [ "${name}" != "${name_prefix}" ]; then
    mkdir -p "${ARCH_DIR_}/${name_prefix}"
  fi

  echo "${name}" >> ${ARCH_RUN_DIR_}/names
  echo "${parameter} ${interval} ${datetime}" >> ${ARCH_RUN_DIR_}/archives

  return 0
}

arch_configure()
{

  local num
  local tags
  local name
  local parameter
  local interval
  local datetime


  for i in "${TEKON_ARCH[@]}"

  do
    tags=$(echo "${i}" | tr " " "\n")
    name=$(grep "name" <<< "${tags}" | cut -d"=" -f2)
    parameter=$(grep "parameter" <<< "${tags}" | cut -d"=" -f2)
    interval=$(grep "interval" <<< "${tags}" | cut -d"=" -f2)
    datetime=$(grep "datetime" <<< "${tags}" | cut -d"=" -f2)

    arch_add "${name}" "${parameter}" "${interval}" "${datetime}"
    result=$? 
    if [ $result -ne 0 ]; then
      fail "${ARCH_LOG_PREFIX_} : invalid archive at '${i}' (archive № $num)"
    fi

    num=$((num+1))
  done

}

arch_init()
{
  log_info "${ARCH_LOG_PREFIX_} : start init"

  # Чтение архивов разрешено? Определяется по наличии переменной в конфиге
  arch_is_enabled
  result=$?
  if [ $result -ne 0 ]; then
    log_warn "${ARCH_LOG_PREFIX_} : service disabled. Variable 'TEKON_ARCH' not set"
    return 1
  fi

  # Проверить окружение
  arch_env_test
  result=$?
  if [ $result -ne 0 ]; then
    fail "${ARCH_LOG_PREFIX_} : environment is invalid"
  fi


  ARCH_NAME_=()         
  ARCH_PARAM_=()        
  ARCH_INTERVAL_=()     
  ARCH_DATETIME_=()     

  ARCH_LAST_READ_=0
  ARCH_INIT_DONE_=0
  ARCH_CURRENT_=0

  ARCH_DIR_="${TEKON_WORKDIR}/arch"
  ARCH_RUN_DIR_="${TEKON_WORKDIR}/arch-runtime"

  # Подготовить коренвые директории
  rm -rf "${ARCH_DIR_}"
  rm -rf "${ARCH_RUN_DIR_}"

  mkdir -p "${ARCH_DIR_}"
  mkdir -p "${ARCH_RUN_DIR_}"

  # Настроить архивы
  arch_configure

  log_info "${ARCH_LOG_PREFIX_} : measurments storage: ${ARCH_DIR_}"
  log_info "${ARCH_LOG_PREFIX_} : temporary storage: ${ARCH_RUN_DIR_}"
  log_info "${ARCH_LOG_PREFIX_} : archives: ${#ARCH_NAME_[*]}"
  log_info "${ARCH_LOG_PREFIX_} : stop init"

  return 0
}

arch_read()
{
  arch_is_enabled
  result=$?
  if [ $result -ne 0 ]; then
    fail "${ARCH_LOG_PREFIX_} : attempt to run disabled service"
  fi

  log_debug "${ARCH_LOG_PREFIX_} : check conditions"
  log_debug "${ARCH_LOG_PREFIX_} : current index ${ARCH_CURRENT_}"
  log_debug "${ARCH_LOG_PREFIX_} : lazy mode ${ARCH_INIT_DONE_}"
  log_debug "${ARCH_LOG_PREFIX_} : last read ${ARCH_LAST_READ_}"

  # Если первоначальное чтение архивов не выполнено, то чтение выполняется
  # каждый цикл. 
  # Иначе - через интервал TEKON_ARCH_POLL_TIME

  local run=1
  local now
  local est
  if [ ${ARCH_INIT_DONE_} -ne 0 ]; then

    now=$(date -u +%s)
    est=$((now - ARCH_LAST_READ_))
    est="${est#-}" #хитрованский способ убрать -

    if [ ${est} -lt "${TEKON_ARCH_POLL_TIME}" ]; then
      run=0
    fi
  fi

  if [ ${run} -eq 0 ]; then
    return 1
  fi

  log_info "${ARCH_LOG_PREFIX_} : start archive reading"

  # Прочитать
  local archive=${ARCH_PARAM_[$ARCH_CURRENT_]}
  local interval="${ARCH_INTERVAL_[$ARCH_CURRENT_]}"
  local datetime="${ARCH_DATETIME_[$ARCH_CURRENT_]}"

  log_debug "${ARCH_LOG_PREFIX_} : read '${archive} ${interval} ${datetime}'"

  ${TEKON_ARCH_BACKEND} -a"${TEKON_ADDRESS}" \
    -t"${TEKON_TIMEOUT_MS}" \
    -p"${archive}" \
    -i"${interval}" \
    -d"${datetime}" \
    > "${ARCH_RUN_DIR_}/last_arch" 2>"${ARCH_RUN_DIR_}/last_error"

  # Скопировать архив или вывести информацию об ошибке
  result=$?
  if [ $result -ne 0 ]; then
    log_warn "${ARCH_LOG_PREFIX_} : archive '${archive}' read error [${ARCH_RUN_DIR_}/last_error]"
    sleep 1 # Если Тэкон не ответил за нужный таймаут, это еще не значит, что он
    # не ответит чуть позже. Лучше немного выждать
  else
    cp "${ARCH_RUN_DIR_}/last_arch" "${ARCH_DIR_}/${ARCH_NAME_[${ARCH_CURRENT_}]}"
  fi

  ARCH_LAST_READ_=${now}
  ARCH_CURRENT_=$(("$ARCH_CURRENT_" + 1))
  if [ ${ARCH_CURRENT_} -ge "${#ARCH_NAME_[@]}" ]; then
    ARCH_CURRENT_=0
    ARCH_INIT_DONE_=1
  fi

  log_info "${ARCH_LOG_PREFIX_} : stop archive reading"

}
