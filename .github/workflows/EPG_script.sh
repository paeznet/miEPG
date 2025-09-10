#!/bin/bash

# Elimina líneas vacías o con solo espacios en epgs.txt
sed -i '/^ *$/d' epgs.txt
# Elimina líneas vacías o con solo espacios en canales.txt
sed -i '/^ *$/d' canales.txt

# Borra cualquier archivo temporal previo que empiece por EPG_temp
rm -f EPG_temp*

# Bucle: lee cada línea de epgs.txt (URLs de EPG) separadas por coma
while IFS=, read -r epg
do
  # Extrae la extensión del archivo (lo que está tras el último punto)
  extension="${epg##*.}"

  # Si el archivo termina en .gz → descargar y descomprimir
  if [ $extension = "gz" ]; then
    echo Descargando y descomprimiendo epg
    wget -O EPG_temp00.xml.gz -q ${epg}       # Descarga en silencio a EPG_temp00.xml.gz
    gzip -d -f EPG_temp00.xml.gz              # Descomprime forzadamente
  else
    # Si no es .gz → descargar tal cual a EPG_temp00.xml
    echo Descargando epg
    wget -O EPG_temp00.xml -q ${epg}
  fi

  # Añade (concatena) el XML descargado al archivo acumulador EPG_temp.xml
  cat EPG_temp00.xml >> EPG_temp.xml

# Fin del bucle leyendo de epgs.txt
done < epgs.txt

# Segundo bucle: lee cada línea de canales.txt separando por comas (old,new,logo)
while IFS=, read -r old new logo
do
  # Cuenta cuántas veces aparece channel="old" en EPG_temp.xml
  contar_channel="$(grep -c "channel=\"$old\"" EPG_temp.xml)"

  # Solo actúa si hay más de 1 coincidencia
  if [ $contar_channel -gt 1 ]; then

    # Extrae el bloque del canal original <channel id="old">...</channel> a EPG_temp01.xml
    sed -n "/<channel id=\"${old}\">/,/<\/channel>/p" EPG_temp.xml > EPG_temp01.xml

    # Deja solo líneas con <icon src> (borra las demás)
    # sed -i '/<icon src/!d' EPG_temp01.xml

    # Si se ha especificado logo nuevo
    if [ "$logo" ]; then
      echo Nombre EPG: $old · Nuevo nombre: $new · Cambiando logo ··· $contar_channel coincidencias

      # Añade cierre de canal
      echo '  </channel>' >> EPG_temp01.xml
      # Inserta nueva cabecera del canal
      sed -i "1i\  <channel id=\"${new}\">" EPG_temp01.xml
      # Inserta nuevo nombre a mostrar
      sed -i "2i\    <display-name>${new}</display-name>" EPG_temp01.xml
      # Sustituye icono existente por nuevo logo
      sed -i "s#<icon src=.*#<icon src=\"${logo}\" \/>#" EPG_temp01.xml
      # Inserta línea con nuevo logo
      sed -i "3i\    <icon src=\"${logo}\" \/>" EPG_temp01.xml  

    else
      # Si no hay logo nuevo, mantiene el actual pero cambia nombre e ID
      echo Nombre EPG: $old · Nuevo nombre: $new · Manteniendo logo ··· $contar_channel coincidencias
      echo '  </channel>' >> EPG_temp01.xml
      sed -i "1i\  <channel id=\"${new}\">" EPG_temp01.xml
      sed -i "2i\    <display-name>${new}</display-name>" EPG_temp01.xml
    fi

    # Añade el bloque de canal modificado al acumulador EPG_temp1.xml
    cat EPG_temp01.xml >> EPG_temp1.xml

    # Elimina líneas duplicadas consecutivas del archivo temporal
    sed -i '$!N;/^\(.*\)\n\1$/!P;D' EPG_temp1.xml

    # Extrae todos los programas del canal original
    sed -n "/<programme.*\"${old}\"/,/<\/programme>/p" EPG_temp.xml > EPG_temp02.xml
    # Limpia atributos en líneas <programme ...>
    sed -i '/<programme/s/\">.*/\"/g' EPG_temp02.xml
    # Quita atributo channel="old"
    sed -i "s# channel=\"${old}\"##g" EPG_temp02.xml	
    # Añade marcador temporal con channel="new"
    sed -i "/<programme/a EPG_temp channel=\"${new}\">" EPG_temp02.xml
    # Sustituye marcador EPG_temp por nada (para dejar bien el XML)
    sed -i ':a;N;$!ba;s/\nEPG_temp//g' EPG_temp02.xml
    # Añade los programas modificados al acumulador EPG_temp2.xml
    cat EPG_temp02.xml >> EPG_temp2.xml

  else
    # Si no hay coincidencias suficientes, salta canal
    echo Saltando canal: $old ··· $contar_channel coincidencias
  fi

# Fin del bucle leyendo de canales.txt
done < canales.txt

# Genera nombre y fecha actual
date_stamp=$(date +"%d/%m/%Y %R")

# Crea miEPG.xml con cabecera XML y datos generador
echo '<?xml version="1.0" encoding="UTF-8"?>' > miEPG.xml
echo "<tv generator-info-name=\"miEPG $date_stamp\" generator-info-url=\"https://github.com/davidmuma/miEPG\">" >> miEPG.xml

# Añade canales y programas ya modificados
cat EPG_temp1.xml >> miEPG.xml
cat EPG_temp2.xml >> miEPG.xml

# Cierra la etiqueta principal
echo '</tv>' >> miEPG.xml

# Limpia todos los archivos temporales
rm -f EPG_temp*