#!/bin/bash

# Check command line arguments
for ARG in "$@"; do
  if [ "${ARG}" == "--help" ] || [ ${ARG} == "-h" ]; then
    echo -e "This tools searches for all 'TODO:' comments in the git history differennce between the current\nbranch and the master.dev branch and writes the output to check-git-added-todos.log. Additionally,\nall 'TODO:' comments occurring in the current branch are written to check-git-all-todos.log"
    echo ""
    echo "Input arguments:"
    echo ""
    echo "  --help/-h            Print this help information."
    echo ""
    echo "Usage example:"
    echo ""
    echo "  cd ~/piclas && ./tools/find-todos-in-git-repository.sh"
    echo ""
    echo "Output:"
    echo ""
    echo "  check-git-added-todos.log : TODOs added in the current branch as comared with the master.dev branch"
    echo "    check-git-all-todos.log : TODOs found in the current branch"
    exit 0
  fi
done

FEATUREBRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ -z ${FEATUREBRANCH} ]] && echo "ERROR: empty branch: ${FEATUREBRANCH}" && exit 1
FBTODOS=$(git diff master.dev...${FEATUREBRANCH} | grep -i todo)
# echo "$FBTODOS"
rm -f check-git-added-todos.log check-git-all-todos.log check-git-added-todos.csv

if [[ -n "${FBTODOS}" ]]; then
  # Loop over all lines containing "todo"
  while read LINE; do
    # Only consider lines beginning with "+"
    if [[ "$LINE" == "+"* ]]; then
      # Cut away the "+" from the beginning of the line
      LINE="${LINE:1}"
      # Additional info
      PREFIX='+'
    elif [[ "$LINE" == "-"* ]]; then
      # Go to next line
      continue
    else
      # Do nothing
      # echo "Ignoring: $LINE"
      PREFIX=' '
    fi

    # Replace " with \"
    LINEESCAPE=${LINE//\"/\\\"}
    # Replace * with \*
    LINEESCAPE=${LINEESCAPE//\*/\\\*}
    # grep all .f90 files for the line identified above
    FOUNDS=$(grep --color=auto -nri --exclude-dir=share --include=*.f90 "${LINEESCAPE}")
    # Loop over all matches
    while read FOUND; do
      # echo $FOUND
      # get the file name of the matching line
      FILE=$(echo ${FOUND} | cut -d ":" -f1)
      # get the file name of the matching line
      LINENBR=$(echo ${FOUND} | cut -d ":" -f2)
      # get rest without the file name
      REST=$(echo ${FOUND} | cut -d ":" -f3-)
      # get git blame information for the matching line
      GITBLAME=$(git log --pretty=format:"%h;%x03%an;%x03%ad;%x03%s" -S"${LINE}" -- ${FILE})
      # Output into to file
      printf "%s;%s;+%s;%s;%s\n" "${PREFIX}" "${FILE}" "${LINENBR}" "${REST}" "${GITBLAME:0:150}" >> check-git-added-todos.log
    done <<< "$FOUNDS"
  done <<< "$FBTODOS"

  if [[ -f check-git-added-todos.log ]]; then
    # Remove duplicate lines
    awk -i inplace '!seen[$0]++' check-git-added-todos.log
    column -s ";" -t check-git-added-todos.log
    wc -l check-git-added-todos.log
    cp check-git-added-todos.log check-git-added-todos.csv
  fi
fi

git grep --color=auto -ni 'todo' | perl -F':' -anpe '$_=`git blame -L$F[1],+1 $F[0]`' | grep -v "TODO-DEFINE-PARAMETER\|ReacTodo\|segmentToDOF\|PathTodo\|RelaxToDo" > check-git-all-todos.log
wc -l check-git-all-todos.log