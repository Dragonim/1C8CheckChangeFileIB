# Описание: Скрипт позволяет убедиться что файловая ИБ не была изменена во время копирования
# Автор: Dim
# Версия: 1.03

param([switch]$Before = $false, # установите данный флаг, если скрипт запускается до начала резервного копирования
      [switch]$After = $false, # установите данный флаг, если скрипт запускается после резервного копирования      
      [string]$FolderIBpath = "c:\1CIB", # Путь к папке файловой ИБ (можно посмотреть в диалоге запуска, если вы не до конца знаете что это)
      [string]$FolderIBlogin = "", # Логин для входа в папку с ИБ, можно не указывать если у пользователя от имени которого запускается скрипт имеются права доступа
      [string]$FolderIBpassword = "", # Пароль для входа в папку с ИБ, можно не указывать если у пользователя от имени которого запускается скрипт имеются права доступа
      [string]$EmailFrom = "test@mail.ru", # Адрес отправителя
      [string]$EmailTo = "test@mail.ru", # Адрес получателя
      [string]$EmailHost = "smtp.mail.ru", # SMTP адрес сервер отправки электронных писем
      [string]$EmailPort = "587", # порт SMTP сервера (если порт отличен от 25 то будет установлен тип шифрования SSL) [для яндекса и мейл.ру надо использовать порт 587]
      [string]$EmailLogin = "test@mail.ru", # Логин для доступа к электронной почте для отправки сообщения
      [string]$EmailPassword = "", # Пароль для доступа к электронной почте для отправки сообщения
      [switch]$EmailTest = $false, # проверка настроек электронной почты (логика скрипта не будет выполнена)
      [string]$TelegramToken = "", # Токен телеграмм бота
      [string]$TelegramChatID = "", # ИД пользователя которому будет отправлено сообщение от имени телеграмм бота
      [switch]$TelegramTest = $false, # проверка настроек телеграмм бота
      [string]$Messengers = "mt", # m - email, t - telegram, e -- вывод сообщений об ошибках в консоль
      [switch]$LockIB = $false, # установите данный флаг, если необходимо заблокировать ИБ от изменений
      [int]$LockTime = 300, # время в секундах на которое будет заблокирована база, если ноль, то блокировка перманентная
      [int]$HashsumTimeout = 60, # время в секундах между созданием файла блокировки и получением хеш-суммы файла. За это время платформа должна успеть выбросить всех пользователей из ИБ
      [string]$HealthСheck = "") # Пароль для доступа к электронной почте для отправки сообщения
 
#################### Объявление и мутация глобальных переменных

# добавляем в конец пути обратный слэш, если такого там нет
if (-not $FolderIBpath.EndsWith('\')) {$FolderIBpath = $FolderIBpath + '\'}

$PathIB = $FolderIBpath + '1Cv8.1CD'
$PathLockFile = $FolderIBpath + '1Cv8.cdn'

# Если переданы данные доступа для каталога с файловой ИБ, то надо их использовать
$FolderIBcredential = ""
if ($FolderIBlogin) {
    $Pass = ConvertTo-SecureString $FolderIBpassword -AsPlainText -Force
    $FolderIBcredential = New-Object System.Management.Automation.PSCredential($FolderIBlogin , $Pass)
}

########################################## начало функций
function SendMessage($Message) {

    # электронное письмо
    if (($EmailFrom -and $EmailTo -and $EmailHost -and $EmailLogin -and $EmailPassword -and $EmailPort -and ($Messengers -match 'm')) -or $EmailTest)  {

        $Pass = ConvertTo-SecureString $EmailPassword -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential($EmailLogin , $Pass)  
    
        $a = @{
            From = $EmailFrom
            To = $EmailTo
            SmtpServer = $EmailHost
            Port = [int32]$EmailPort
            Credential = $Credential
            Subject = $Message
            Body = $Message
            Encoding = 'UTF8'
        }
    
        try {
            if ($EmailPort -eq "25") {
                Send-MailMessage @a -ErrorAction 'stop'
            } else {
                Send-MailMessage @a -UseSsl -ErrorAction 'stop'
            }
            if ($EmailTest) {
                Write-Output "Тестовое письмо отправлено на $EmailTo"
            }

        } catch {
            Write-Output "Не удалось отправить письмо"
        }    
    }

    # сообщение от бота в телеграмм
    if (($TelegramToken -and $TelegramChatID -and ($Messengers -match 't')) -or $TelegramTest) {
        try {
            $URI = "https://api.telegram.org/bot" + $TelegramToken + "/sendMessage?chat_id=" + $TelegramChatID + "&text=" + $Message
            Invoke-WebRequest -URI ($URI) -ErrorAction 'stop' | Out-Null
            if ($TelegramTest) {
                Write-Output "Тестовое собщение в телеграм отправлено"
            }        
        } catch {
            Write-Output "Не удалось отправить сообщение в телеграмм"
        }    
    }

    # сообщение в консоль
    if ($Messengers -match 'e') {
        Write-Error $Message          
    }
    
}

function TestPathCredential($Path) {
    $flag = $false

    if ($FolderIBcredential) {
        $flag = Test-Path -Path $Path -Credential $FolderIBcredential
    } else {
        $flag = Test-Path -Path $Path 
    }

    return $flag
}

function CreateLockFile() {

    $text = '{1,' + `
        + (Get-Date -Format "yyyyMMddHHmmss") `
        + ',' `
        + (Get-Date -Date (Get-Date).AddSeconds($LockTime) -Format "yyyyMMddHHmmss") `
        + ',"Backup","StopBackup","",0}'
    
    try {
        if ($FolderIBcredential) {
            New-Item -Path $PathLockFile -Value $text -Force -Credential $FolderIBcredential | Out-Null 
        } else {
            New-Item -Path $PathLockFile  -Value $text -Force | Out-Null 
        }

        return $true

    }
    catch {
        SendMessage "Не удалось создать файл блокировки информационной базы в папке $FolderIBpath"   
        return $false
    }

}

function DeleteLockFile() {

    if (TestPathCredential $PathLockFile) {
        try {
            if ($FolderIBcredential) {
                Remove-Item -Path $PathLockFile -Force -Credential $FolderIBcredential | Out-Null 
            } else {
                Remove-Item -Path $PathLockFile -Force | Out-Null 
            }
        }
        catch {
            SendMessage "Не удалось удалить файл блокировки информационной базы $PathLockFile"
        }
    }
}

function DeleteHashFile() {
    if (Test-Path $HashFile) {
		Remove-Item -Path $HashFile -Force | Out-Null 
    }
}

function  GetPathHashFile() {
    $str = $FolderIBpath.Replace(':', '')
    $str = $str.Replace('\', '')
    $str = $env:TEMP + '\' + $str + '.sha1' 
    return $str
}

function GetHash($File) {
    $Prog = $env:TEMP + '\' + 'sha1sum.exe'    

    # к сожалению Get-FileHash не может получить хеш используемого файла, поэтому необходимо пользоваться внешней программой    
    # возможно программа для получения хеш суммы была скачена ранее, проверим это
    if (-not (Test-Path $Prog))  {  
        Invoke-WebRequest "ftp://ftp.gnupg.org/gcrypt/binary/sha1sum.exe" -OutFile $Prog   
    }

    if (Test-Path $Prog) {
        try {
        
            $TempFile = $env:TEMP + '\' + [System.IO.Path]::GetRandomFileName()           

            if ($FolderIBcredential) {
                Start-Process -FilePath $Prog -ArgumentList ('"' + $File + '"') -NoNewWindow -Wait -RedirectStandardOutput $TempFile -Credential $FolderIBcredential -ErrorAction "Stop"               
            } else {                
                Start-Process -FilePath $Prog -ArgumentList ('"' + $File + '"') -NoNewWindow -Wait -RedirectStandardOutput $TempFile -ErrorAction "Stop"    
                #$hash = ((& $Prog $File).Split(' '))[0] 
            }

            $hash = Get-Content -Path $TempFile
            $hash = ($hash.Split(' '))[0]
        
        } catch {
            $hash = ""
        }
    }

    if (-not $hash) {
        try {
            $hash = (Get-FileHash -Path $File -Algorithm SHA1 -ErrorAction "Stop").Hash
        } catch {        
            SendMessage "Не удалось получить хэш сумму файла $File"
            return ""
        }   
    }

    return $hash.ToUpper()
}

########################################## конец функций

if ($EmailTest) {
    SendMessage "Проверка связи"
    exit 0
}

if ($TelegramTest) {
    SendMessage "Проверка связи"
    exit 0
}

# проверим, имеется ли файл ИБ
if (-not (TestPathCredential $PathIB)) {    
    SendMessage "Не найден файл 1Cv8.1CD в папке $FolderIBpath"
    exit 4
}

$HashFile = GetPathHashFile

if (-not ($Before -or $After)) {
    SendMessage "Скрипт запущен без указания параметров -Before или -After"
    exit 4
}

if ($Before -and $After) {
    SendMessage "Нельзя запускать скрипт указывая одновременно параметры -Before и -After"
    exit 4
}

# коды выхода из скрипта для программы duplicati
# https://github.com/duplicati/duplicati/blob/master/Duplicati/Library/Modules/Builtin/run-script-example.bat
$ExitCode = 0

if ($Before) {

    if ($LockIB) {
        if (CreateLockFile) {
            Start-Sleep -Seconds $HashsumTimeout
        } else {
            $ExitCode = 4    
        }
    }    
    
    $hash = GetHash($PathIB)
    try {
		New-Item -Path $HashFile -Value $hash -Force | Out-Null 
    }
    catch {
        SendMessage "Не удалось создать файл с хэш-суммой $HashFile"  
		$ExitCode = 4
    }

}

if ($After) {    
    
    $NewHash = GetHash($PathIB)
    try {
		$OldHash = Get-Content -Path $HashFile
    }
    catch {
        SendMessage "Не удалось прочитать файл с хэш-суммой $HashFile"
        $ExitCode = 4		
    }
    
    if ($OldHash -ne $NewHash) {
        SendMessage "Файловая информационная база $PathIB была изменена. Если производилось резервное копирование, то велика вероятность нарушения целостности резервной копии ИБ"
        $ExitCode = 4
    }

	DeleteHashFile
	
    if ($LockIB) {
        DeleteLockFile
    }    

    if ($HealthСheck) {
        Invoke-RestMethod $HealthСheck
    }    

}

exit $ExitCode