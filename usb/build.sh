#!/bin/bash
# Экспорт скрипта
echo -n "Build..."
OUT=tekon_usb
cat tekon_usb.sh > ${OUT}

result=$?
if [ $result -eq 0 ]; then
  echo "OK"
else
  echo "Fail"
  exit 1
fi

chmod +x ${OUT}

