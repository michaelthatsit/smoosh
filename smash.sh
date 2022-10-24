#!/bin/bash
# SMASH, a simple static website generator in bash.
# Based on Statix (c) Revoltech 2015 - the simplest static website generator in bash
# Improved 2022 by Laurent Baumann - hello@lobau.io

# Data files and folders
routeFile='routes.conf'
dataFile='data.conf'
templateFolder='source'
outputFolder='output'
assetFolder='source/static'

#routines

function prerenderTemplate {
    local TPLFILE="${templateFolder}/$1"
    local TPLCONTENT="$(<$TPLFILE)"
    OLDIFS="$IFS"
    IFS=$'\n'
    
    # INCLUDES
    # Insert the content of a file into another
    # Most common case is to include footer, or navigation
    # Example: <!--#include:_include/_footer.html-->
    # ---------------------------------------------------------------
    local empty=''
    local INCLUDES=$(grep -Po '<!--\s*#include:.*-->' "$TPLFILE")
    for empty in $INCLUDES; do
        local INCLFNAME=$(echo -n "$empty"|grep -Po '(?<=#include:).*?(?=-->)')
        local INCLFCONTENT="$(prerenderTemplate ${INCLFNAME})"
        TPLCONTENT="${TPLCONTENT//$empty/$INCLFCONTENT}"
    done
    
    # DATA MODULES
    # It currently break if you have more then one per page. Grep is not the right tool.
    # In your HTML markup, use <!--#module:test.csv#template:_include/_block.html-->
    # For each entry in the csv file, a module will be inserted inline.
    # The values in the csv are applied to the variabled in the template
    # For example, the values in the column "name" in the csv will remplate {{name}} templates
    # ---------------------------------------------------------------
    local MODULES=$(grep -Po '<!--\s*#module:.*:.*-->' "$TPLFILE")
    for empty in $MODULES; do
        local MODDATA=$(echo -n "$empty"|grep -Po '(?<=#module:).*?(?=#template:)')
        local MODTPLT=$(echo -n "$empty"|grep -Po '(?<=#template:).*?(?=-->)')
        
        # Load the data file (csv) and iterate over it
        local MODdataFile="${templateFolder}/$MODDATA"
        local MODTPLTFILE="${templateFolder}/$MODTPLT"
        local ModuleTemplateContent="$(<$MODTPLTFILE)"
        
        # Map the csv file to a 1D array, one row per line
        IFS=$'\n' mapfile -t csvArray < $MODdataFile
        
        # Store the keys in an array for later (the first line of the csv file)
        IFS='|' read -ra keyArray <<< "${csvArray[0]}"

        MODOUTPUT=""
        for ((i = 1; i < ${#csvArray[@]}; ++i)); do
                IFS='|' read -ra valuesArray <<< "${csvArray[$i]}"
                local templateOutput="$(<$MODTPLTFILE)"
                for ((j = 0; j < ${#valuesArray[@]}; ++j)); do
                    templateOutput="${templateOutput//<!--@${keyArray[$j]}-->/${valuesArray[$j]}}"
                    templateOutput="${templateOutput//\{\{${keyArray[$j]}\}\}/${valuesArray[$j]}}"
                done
                MODOUTPUT+="$templateOutput"
        done
        TPLCONTENT="${TPLCONTENT//$empty/$MODOUTPUT}"
    done

    # INLINE BASH
    # Use to run bash inline: <!--#bash:echo Hello World!-->
    # Can be used in footer for copyright info for example
    # <!--#bash:date +"%Y"--> — All Rights Reserved
    # ---------------------------------------------------------------
    local SCRIPTS=$(grep -Po '<!--\s*#bash:.*-->' "$TPLFILE")
    for empty in $SCRIPTS; do
        local COMMAND=$(echo -n "$empty"|grep -Po '(?<=#bash:).*?(?=-->)')
        local OUTPUTCONTENT=$(eval $COMMAND)
        TPLCONTENT="${TPLCONTENT//$empty/$OUTPUTCONTENT}"
    done
    
    IFS="$OLDIFS"
    echo -n -e "$TPLCONTENT"
}

function renderTemplate {
    local TPLTEXT="$(prerenderTemplate $1)"
    local SETS=$(echo -n "$TPLTEXT"|grep -Po '<!--#set:.*?-->')
    local L=''
    OLDIFS="$IFS"
    IFS=$'\n'
    
    # Local variables with <!--#set-->
    for L in $SETS; do
        local SET=$(echo -n "$L"|grep -Po '(?<=#set:).*?(?=-->)')
        local SETVAR="${SET%%=*}"
        local SETVAL="${SET#*=}"
        TPLTEXT="${TPLTEXT//$L/}"
        TPLTEXT="${TPLTEXT//\{\{${SETVAR}\}\}/${SETVAL}}"
    done
    
    # Global variables from the dataFile
    DATALIST="$(<$dataFile)"
    for DATA in $DATALIST; do
        DATANAME="${DATA%%:*}"
        DATAVAL="${DATA#*:}"
        TPLTEXT="${TPLTEXT//\{\{${DATANAME}\}\}/${DATAVAL}}"
    done

    # remove empty lines
    local TPLTEXT=$(echo -n "$TPLTEXT"|grep -v '^$')
    
    IFS="$OLDIFS"
    echo -n -e "$TPLTEXT"
}

#run main action

mkdir -p "$outputFolder"
rm -rf "${outputFolder}"/*
echo "🧹 Cleaned up $(tput bold)/$outputFolder/$(tput sgr0) folder"
if [[ "$assetFolder" ]]; then cp -rd "$assetFolder" "${outputFolder}/" && echo "🎨 Copied $(tput bold)/$assetFolder/$(tput sgr0) assets folder";fi
ROUTELIST="$(<$routeFile)"
OLDIFS="$IFS"
IFS=$'\n'

for ROUTE in $ROUTELIST; do
    TPLNAME="${ROUTE%%:*}"
    TPLPATH="${ROUTE#*:}"
    if [[ "$TPLNAME" && "$TPLPATH" ]]; then
        mkdir -p "${outputFolder}${TPLPATH}"
        renderTemplate "$TPLNAME" > "${outputFolder}${TPLPATH}index.html"
        echo "✨ Rendered $TPLNAME to $(tput bold)$TPLPATH$(tput sgr0)"
    fi
done

IFS="$OLDIFS"

echo "🎀 The website is ready!"
echo ""
