#!/bin/bash

libreoffice -unnaccept=all -headless -invisible -nocrashreport -nodefault -nologo -nofirststartwizard -norestore -convert-to swf:impress_flash_Export $PATH_TO_FILE

libreoffice -unnaccept=all -headless -invisible -nocrashreport -nodefault -nologo -nofirststartwizard -norestore -convert-to html:'HTML (StarWriter)' $PATH_TO_FILE
