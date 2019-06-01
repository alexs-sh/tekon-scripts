#============================================================================== 
# Модуль с общими функциями
#============================================================================== 
LOG_RED_='\033[1;31m'
LOG_YELLOW_='\033[1;33m'
LOG_PURPLE_='\033[0;35m'
LOG_NOCOL_='\033[0m' # No Color
LOG_LEVEL_=2

log_err()
{
  if [ $LOG_LEVEL_ -gt 0 ]; then
    echo -e "${LOG_RED_}[$(date -u +%s)] : ERR : $$ $1 ${LOG_NOCOL_}" 
  fi
}

log_warn()
{
  if [ $LOG_LEVEL_ -gt 1 ]; then
    echo -e "${LOG_YELLOW_}[$(date -u +%s)] : WRN : $$ $1 ${LOG_NOCOL_}" 
  fi
}

log_info()
{
  if [ $LOG_LEVEL_ -gt 2 ]; then
    echo -e "${LOG_NOCOL_}[$(date -u +%s)] : INF : $$ $1 ${LOG_NOCOL_}" 
  fi
}

log_debug()
{
  if [ $LOG_LEVEL_ -gt 3 ]; then
    echo -e "${LOG_PURPLE_}[$(date -u +%s)] : DBG : $$ $1 ${LOG_NOCOL_}" 
  fi
}

log_level()
{
  LOG_LEVEL_=$1
}

fail()
{
  log_err "$1"
  exit 1
}


