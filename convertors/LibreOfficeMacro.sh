#copy all .libreoffice directory to ~/.libreoffice

libreoffice -unnaccept=all -headless -invisible -nocrashreport -nodefault -nologo -nofirststartwizard -norestore "macro:///Standard.Module1.SaveAsDoc($PATH_TO_FILE)"
