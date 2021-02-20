


git.exe checkout -f master --
@IF %ERRORLEVEL% NEQ 0 GOTO END

git.exe pull --progress -v --no-rebase "git@github.com:pascalabcnet/pascalabcnet.git" master
@IF %ERRORLEVEL% NEQ 0 GOTO END

git.exe push --progress "origin" master:master
@IF %ERRORLEVEL% NEQ 0 GOTO END

git.exe checkout custom-build --
@IF %ERRORLEVEL% NEQ 0 GOTO END

git.exe merge master
@IF %ERRORLEVEL% NEQ 0 GOTO END

git.exe push --progress "origin" custom-build:custom-build
@IF %ERRORLEVEL% NEQ 0 GOTO END



_GenerateAllSetups.bat
:END
PAUSE