#!/bin/bash

APP_NAME="tekon_usb"
DEV=""
SRC=""
MNT=/tmp/usbmon
RT=/tmp/usbmon-runtime
NAME="export"
ARCH=""
CS=""
VERBOSE=0

STEP=0
ERR=0
ERRFILE=/tmp/usbmon-runtime/last_error

LOG_LIMIT=1000
LOG_CNT=0

set_step()
{
    if [ "$1" -ne $STEP ]; then
     STEP=$1
     echo "$1" > $RT/step

     if [ $VERBOSE -ne 0 ]; then
       echo "$APP_NAME : INF : $$ : step $1"
     fi
    fi
}

set_error()
{
    if [ "$1" -ne $ERR ]; then
     ERR=$1
     echo "$1" > $RT/error

     if [ "${ERR}" -ne 0 ]; then
       echo "$APP_NAME : ERR : $$ : code $1" 1>&2
     fi
    fi
}

usage()
{
  echo "$APP_NAME -d device -m mountpoint -r runtime dir -s source dir"
  echo ""
  echo "  -d - USB device name"
  echo ""
  echo "  -m - directory used to mount USB"
  echo ""
  echo "  -r - runtime directory"
  echo ""
  echo "  -s - source directory"
  echo ""
  echo "  -v - verbose"
  echo ""
  echo "Example"
  echo "  $APP_NAME -d /dev/sda -m /tmp/tekon_usb/mnt -r /tmp/tekon_usb/runtime -s /tmp/archives"

}

parse_args()
{

  while getopts d:m:r:s:hv arg
  do
    case $arg in
      d)
        DEV=$OPTARG
        ;;
      m)
        MNT=$OPTARG
        ;;
      r)
        RT=$OPTARG
        ;;
      s)
        SRC=$OPTARG
        ;;
      h)
        usage
        exit 0
        ;;
      v)
        VERBOSE=1
        ;;
        \?)
        usage
        exit 1
        ;;
    esac
  done

}


clean_log()
{
  LOG_CNT=$((LOG_CNT+1))  

  if [ $LOG_CNT -ge $LOG_LIMIT ]; then
    LOG_CNT=0
    rm "$ERRFILE" &> /dev/null
    touch "$ERRFILE" &> /dev/null
  fi

}

main()
{

  parse_args "$@"
  
  if [ "$DEV" = "" ]; then
    echo "USB device not set"
    usage
    exit 1
  fi
  
  if [ "$SRC" = "" ]; then
    echo "Source dir not set"
    usage
    exit 1
  fi

  if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root"
   exit 1
  fi

  
  trap 'set_step 99' SIGINT
  
  set_step 0
  set_error 0
  
  ARCH="$RT/$NAME.tar.gz" 
  CS="$RT/$NAME.md5"
  ERRFILE="$RT/last_error"

  mkdir -p "$MNT"
  mkdir -p "$RT"
  
  if [ ! -d "$MNT" ]; then
      echo "Mount point not exists [$MNT]"
      exit 1
  fi
  
  if [ ! -d "$RT" ]; then
      echo "Runtime dir not exists [$RT]"
      exit 1
  fi
  
  rm -f "$ERRFILE"

  while true; do

      clean_log

      case $STEP in
          0)
              # Шаг 0: ожидаем появления файла-устройства. Проще говоря, ждем, когда
              # флешка будет вставлена
              if [ -e "$DEV" ]; then
                  set_step 1
              fi
              ;;
          1)
              # Шаг 1: примонтировать флешку
              # Возможны варианты: на флешке может быть несколько нумерованных (sda1,sda2,..),
              # разделов. А может быть один, но без номера (sda). Все зависит от того, кто и как
              # форматировал флешку. И вряд ли кто-то будет вставлять осмысленно отформатированные
              # флешки. Скорее всего они будут подготовлены штатными средствами Windows, 
              # а она делает как получится. 
              # Пока поступим тупо - пробуем примонтировать устройство. Если получилось - хорошо.
              # Если нет, монтируем 1-й раздел. Если этот метод окажется неэффективным, то я сделаю
              # более сложную логику определения и монтирования флешки
              mount "$DEV" "$MNT" 2>>"$ERRFILE"
              result=$?
              if [ $result -eq 0 ]; then
                  set_step 2
              else
                  mount "${DEV}1" "$MNT" 2>>"$ERRFILE"
                  result=$?
                  if [ $result -eq 0 ]; then
                    set_step 2
                  else
                    set_error 1
                    set_step 5
                fi
              fi
              ;;
          2)
              # Шаг 2: подготовить директории на флешке
              DT=$(date -u +%s)
              FDT=$(date --date="@$DT" +%F)_$(date --date="@$DT" +%H)-$(date --date="@$DT" +%M)-$(date --date="@$DT" +%S)
              OUT=$MNT/tekon_$FDT

              mkdir -p "$OUT" 2>>"$ERRFILE"
              if [ ! -d "$OUT" ]; then
                  set_error 2
                  set_step 5
              else
                  set_step 3
              fi
              ;;
          3)
              # Шаг 3: сжать данные и скопировать их не флеш
              result=1
              if cd "$SRC" 2>>"$ERRFILE" ; then
                tar -czf "$ARCH" ./* 2>>"$ERRFILE"
                cd - > /dev/null || exit
                md5sum "$ARCH" | cut -f1 -d " " > "$CS" 2>>"$ERRFILE"

                # cp + rm предпочтительнее, чем mv. Особенно если мы переносим файлы из одной
                # ФС в другую, имеющую отличную системы прав. А так скорее всего и будет.
                # Т.к. мы потянем из ext/ramfs в FAT или NTFS
                cp "$ARCH" "$CS" "$OUT" 2>>"$ERRFILE"
                result=$?
                sync 2>>"$ERRFILE"
                rm "$ARCH" "$CS"
              fi
  
              # Проверить результат cp. Не забываем, что CP может использовать кэш.
              # Т.е. если сейчас все ОК, это еще не значит, что файлы на флешке.
              # Наличие файлов требует отдельной проверки
              if [ $result -ne 0 ]; then
                set_error 3
                set_step 5
              else
                set_step 4
              fi

              ;;
          4)
  
              # Шаг 4: убедится, что файлы записаны
              if [ ! -f "$OUT/$NAME.tar.gz" ]; then
                  set_error 4
              fi
  
              if [ ! -f "$OUT/$NAME.md5" ]; then
                  set_error 4
              fi
  
              set_step 5
              ;;
          5)
              # Шаг 5: отмонтировать флеш
              umount "$MNT" 2>>"$ERRFILE"
              set_step 6
              ;;
          6)
              # Шаг 6: подождать, когда файл устройства перестанет существовать. 
              # Другими словами, флешка будет извлечена

              if [ "$ERR" -ne 0 ]; then
                  # Повисеть с ошибкой, чтобы ее можно было увидет через статусы
                  sleep 5
              fi

              if [ ! -e "$DEV" ]; then
                  set_error 0
                  set_step 0
              fi
              ;;
          99)
              umount "$MNT" 2>>"$ERRFILE"
              exit 0
              ;;
  
      esac
  
      sleep 0.5
  done
}

main "$@"
