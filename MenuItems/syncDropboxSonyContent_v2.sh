#!/data/data/com.termux/files/usr/bin/bash 
# 0. CONSTANTS
# 0.1 Generic sqlite command
sqlite="/data/data/com.termux/files/usr/bin/sqlite3 /data/data/com.sony.capas.dataaccessprovider/databases/document_database_v2.db"
# 0.2 Base Path
BASEPATH=/storage/emulated/legacy/Android/data/com.dropbox.android/files/u88291057/scratch/DigitalPaper/SonyApp
# 0.3 UNIX Utilities
awk=/data/data/com.termux/files/usr/bin/applets/awk
uniq=/data/data/com.termux/files/usr/bin/applets/uniq
_sort="/data/data/com.termux/files/usr/bin/applets/sort"
cut=/data/data/com.termux/files/usr/bin/applets/cut
# 0.4 Install necessary programs
# pkg install sqlite3
# pkg install tsu


# 1.1 Get a list of all directories (with PDF files in it)
#     1.1.1 Find all the ".pdf" files (find)
#     1.1.2 Strip away the filename, keep the path (sed)
#     1.1.3 Remove duplicates (where more than one PDF file is in a directory, the directory would show multiple times)
OIFS=$IFS; IFS=$'\n'; DIRLIST=($(cd $BASEPATH; find . -type f -name '*.pdf' | sed -r 's|/[^/]+$||' | sort -u )); IFS=$OIFS;
COMPLETEDIRLIST=()
for ((i=0;i<${#DIRLIST[@]};i++));
do
   nestedDir="${DIRLIST[$i]}"
   nestedDir="${nestedDir#./}"
   OIFS=$IFS
   IFS='/'
   PROGRESSIVE_PATH=
   for singleDir in ${nestedDir[@]}
   do
     COMPLETEDIRLIST+=("$PROGRESSIVE_PATH/$singleDir")
     PROGRESSIVE_PATH="$PROGRESSIVE_PATH/$singleDir"
   done
   IFS=$OIFS
done

# 1.2 Sort ascending by length of string (idea: root to leaf)
#OIFS=$IFS; IFS=$'\n'; DIRLIST="$(echo "${COMPLETEDIRLIST[@]}" | $uniq | $awk '{printf "%s\t%s\n", length($0), $0}' | $_sort -n -s | $cut -f 2)"; IFS=$OIFS

# 1.3 Turn it into a BASH array
OIFS=$IFS; IFS=$'\n'; DIRLIST=($(printf '%s\n' "${COMPLETEDIRLIST[@]}" | sort -u )); IFS=$OIFS;

# 2. Get a list of all PDFs
FILELIST="$(cd $BASEPATH; find . -name "*.pdf")"
# 2.1 Turn it into a BASH array
OIFS=$IFS; IFS=$'\n'; FILELIST=($FILELIST); IFS=$OIFS

# 3. Delete the previous cached structure and reset auto_increment indexes
$sqlite "DELETE FROM folder WHERE folder_id LIKE 'dropbox_%' OR document_id LIKE 'dropbox_%'"
LASTID=$($sqlite "SELECT MAX(_id) FROM folder") 
$sqlite "UPDATE SQLITE_SEQUENCE SET SEQ=$(( LASTID + 1 )) WHERE NAME='folder';"

$sqlite "DELETE FROM file WHERE file_id LIKE 'dropbox_%'"
LASTID=$($sqlite "SELECT MAX(_id) FROM file") 
$sqlite "UPDATE SQLITE_SEQUENCE SET SEQ=$(( LASTID + 1 )) WHERE NAME='file';"

$sqlite "DELETE FROM documents WHERE document_id LIKE 'dropbox_%'"
LASTID=$($sqlite "SELECT MAX(_id) FROM documents") 
$sqlite "UPDATE SQLITE_SEQUENCE SET SEQ=$(( LASTID + 1 )) WHERE NAME='documents';"

$sqlite "DELETE FROM page_cache WHERE document_id LIKE 'dropbox_%'"

# 4. DIRECTORIES

# 4.0 Insert the root dropbox folder
$sqlite "INSERT INTO folder 
(item_type,folder_id,folder_name,folder_path,parent_folder_id)
VALUES 
(0,'dropbox_0','Dropbox','Document/Dropbox/','root')
"
# 4.1 Create directories and subdirectories
for ((i=0;i<${#DIRLIST[@]};i++));
do
     dir="${DIRLIST[$i]}"
     LASTID=$($sqlite "SELECT MAX(_id) FROM folder")
     NEWID=$(( LASTID + 1 ))
     NAME="${dir##*/}"
     if [[ "$NAME" == "." ]]; then continue; fi

     # Strip out the parent dir from the path
     PARENTSUBDIR="${dir%/*}"
     PARENTSUBDIR="Document/Dropbox${PARENTSUBDIR#.}/"
     # Get the id of the parent folder
     if [[ "$PARENTSUBDIR" == "Document/" ]]
     then
        PARENTSUBDIRID="dropbox_0"
     else
     	PARENTSUBDIRID=$($sqlite "SELECT folder_id FROM folder WHERE folder_path = '${PARENTSUBDIR//\'/\'\'}' AND item_type = 0;")
     fi
     FOLDERPATH="Document/Dropbox${dir#.}/"
     # SQL insert instruction
     $sqlite "INSERT INTO folder (item_type,folder_id, folder_name, folder_path, parent_folder_id) 
VALUES (0,'dropbox_folder_$NEWID', '$NAME', '$FOLDERPATH','$PARENTSUBDIRID')"
done
 

# 5. Create all the files
# 5.1 In the "files" table
for ((i=0;i<${#FILELIST[@]};i++));
do
     file="${FILELIST[$i]}"
     LASTID=$($sqlite "SELECT MAX(_id) FROM file")
     NAME="${file##*/}"
     NEWID=$(( LASTID + 1 ))
     
     FILESIZE=$(pdfinfo "$BASEPATH/$file" | grep "File size: ")
     FILESIZE=${FILESIZE% bytes}
     FILESIZE=${FILESIZE#File size: }
     AUTHOR="$(pdfinfo "$BASEPATH/$file" | grep "Author: ")"
     AUTHOR="${AUTHOR#Author: }"
     TITLE="$(pdfinfo "$BASEPATH/$file" | grep "Title: ")"
     TITLE="${TITLE#Title: }"
     TOTALPAGES=$(pdfinfo "$BASEPATH/$file" | grep "Pages: ")    
     TOTALPAGES=${TOTALPAGES#Pages: }
     if [ "${file%%*_}" == "note.pdf" ]
     then
     	FILETYPE=1
     else
     	FILETYPE=0
     fi

     $sqlite "INSERT INTO file 
(file_id,
filename,
file_path,
file_size,author,title,total_page,
mime_type,file_type) 
VALUES 
('dropbox_$NEWID',
'${NAME//\'/\'\'}',
'$BASEPATH/${file//\'/\'\'}', 
$FILESIZE,'${AUTHOR//\'/\'\'}','${TITLE//\'/\'\'}',$TOTALPAGES,
'application/pdf',
$FILETYPE)
"

done

# 5.2 In the "documents" table
for ((i=0;i<${#FILELIST[@]};i++));
do
     file="${FILELIST[$i]}"
     # 5.1 Get the last entry number
     LASTID=$($sqlite "SELECT MAX(_id) FROM documents")

     # 5.2 Increment by one
     NEWID=$(( LASTID + 1 ))

     # 5.3 Filter out the filename 
     NAME="${file##*/}"

     # 5.4 Figure out id of the current file (in table: file)
    FILEID=$($sqlite "SELECT file_id FROM file WHERE file_path = '$BASEPATH/${file/\'/\'\'}'")

    # 5.5 Final SQL statement (to create a new document)
    $sqlite "INSERT INTO documents 
(document_id, title, last_read_file_id, orientation) 
VALUES 
('dropbox_$NEWID', '${NAME//\'/\'\'}', '$FILEID',0)
"
done

# 5.2 In the "folder" table
for ((i=0;i<${#FILELIST[@]};i++));
do
     file="${FILELIST[$i]}"
     LASTID=$($sqlite "SELECT MAX(_id) FROM file")
     NAME="${file##*/}"
     NEWID=$(( LASTID + 1 ))
     
     # Strip out the parent dir from the path
     PARENTSUBDIR="${file%/*}"
     PARENTSUBDIR="Document/Dropbox${PARENTSUBDIR#.}/"
     # Get the id of the parent folder
     if [[ "$PARENTSUBDIR" == "Document/" ]]
     then
        PARENTSUBDIRID="dropbox_0"
     else
     	PARENTSUBDIRID=$($sqlite "SELECT folder_id FROM folder WHERE folder_path = '${PARENTSUBDIR//\'/\'\'}' AND item_type = 0;")
     fi
     FOLDERPATH="Document/Dropbox${file#.}"
     FILEID=$($sqlite "SELECT file_id FROM file WHERE file_path = '$BASEPATH/${file//\'/\'\'}'")
     DOCUMENTID=$($sqlite "SELECT document_id FROM documents WHERE last_read_file_id = '$FILEID' ;")

     $sqlite "INSERT INTO folder
(item_type,
document_id,
folder_path,
parent_folder_id) 
VALUES 
(1,
'$DOCUMENTID',
'${PARENTSUBDIR//\'/\'\'}',
'$PARENTSUBDIRID'
)
"

done


