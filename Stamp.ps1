cls

$exit = $false
$version = '1.0'
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic') | Out-Null

function Print-Logo
{
param($Version)

    Write-Host "                     "  -BackgroundColor DarkYellow
    Write-Host " Stamps (v $Version) " -ForegroundColor Black -BackgroundColor DarkYellow
    Write-Host "                     "  -BackgroundColor DarkYellow

}

function Invoke-MySQLQuery
{
Param(
  [string]$Query
)
    $DBcon = [PSCustomObject]@{
        UN = 'bedd43df9a4244'
        PW = '32a88716'
        DB = 'StampDB'
        Host = 'eu-cdbr-azure-north-d.cloudapp.net'
    }

    $string = "server=$($DBcon.Host);port=3306;uid=$($DBcon.UN);pwd=$($DBcon.PW);database=$($DBcon.DB)"

    Try {
      [void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")
      $Connection = New-Object MySql.Data.MySqlClient.MySqlConnection
      $Connection.ConnectionString = $string
      $Connection.Open()

      $Command = New-Object MySql.Data.MySqlClient.MySqlCommand($Query, $Connection)
      $DataAdapter = New-Object MySql.Data.MySqlClient.MySqlDataAdapter($Command)
      $DataSet = New-Object System.Data.DataSet
      $RecordCount = $dataAdapter.Fill($dataSet, "data")
      $msg = 'Query successfull'
      $status = $true
      }

    Catch
    {
        $status = $false
        $msg = $_.exception.message
    }

    Finally
    {
        $Connection.Close()
    }

    return [pscustomobject]@{
        Status = $status
        Data = $DataSet.Tables[0]
        LastInsertedID = $Command.LastInsertedId
        Message = $msg
    }

}

function ConvertTo-PlainText
{
param($string)

        $s = ConvertTo-SecureString $string
        $s = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
        $s = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($s)

    return $s
}

function Prompt-Password
{
param(
[switch] $AsHash
)

    $readPW = Read-Host "Enter password" -AsSecureString
    $cc1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($readPW)
    $cc1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($cc1)

    if($AsHash)
    {
        return Hash-String -string $cc1
    }

    return $cc1
}

function New-Salt
{
    $key = New-Object byte[](32)
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $rng.GetBytes($key)
    return [System.Convert]::ToBase64String($key)
}

function Hash-String
{
param($string,$Cost = 10,$Salt)

    $iteration = [math]::Pow(2,$cost)

    if(!$salt)
    {
        $salt = New-Salt
    }

    $string = $string + $salt

    1..$iteration | %{ 
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        $enc = [system.Text.Encoding]::UTF8
        $bytes = $enc.GetBytes($string) 
        $string = [System.Convert]::ToBase64String($hasher.ComputeHash($bytes))
    }

    return [pscustomobject]@{
        Salt = $salt
        Hash = $string
    }
}

function Test-PW
{
param($Username, $Password)

    $record = Get-UserFromDB -Join "join Login on Login.UserID = Users.UserID Where Email = '$Username'"

    if($record.Status)
    {
        if((Hash-String -string $Password -salt $record.data.Salt).Hash -eq $record.data.Hash)
        {
            return $true
        }
    }

    return $false
}

function Get-UserFromDB
{
param(
    [string] $Filter,
    [string] $Join
)
    if($Join)
    {  
       $q = "SELECT * from Users $Join"         
    }
    ElseIf($Filter)
    {
        $q = "SELECT * from Users where $Filter"
    }
    else
    {
        $q = "SELECT * from Users"
    }

    return Invoke-MySQLQuery -Query $q
}

function Get-Stamps
{
param($UserID)

    $q = "SELECT CompanyName,DiscountName,Description,COUNT(*) as Stamps,CountToCollect from Users 
    join Stamps on Stamps.UserID = Users.UserID
    join Discount on Stamps.DiscountID = Discount.DiscountID
    join Company on Discount.CompanyID = Company.CompanyID
    where Users.UserID = $UserID"

    return Invoke-MySQLQuery -Query $q
}

function Add-StampToCustomer
{
param($DiscountID,$CustomerID)

    $q = "INSERT INTO Stamps (DiscountID, UserID) VALUES ($DiscountID, $CustomerID)"
    return Invoke-MySQLQuery -Query $q
}

function Add-UserToDB
{
param(
    [string] $Firstname,
    [string] $Lastname,
    [string] $Email,
    [string] $Address,
    [string] $Postalcode,
    [string] $City,
    [string] $Country,
    [string] $BD,
    [string] $Hash,
    [string] $Salt
)

    try
    {
        $Firstname = $Firstname.substring(0,1).toupper() + $Firstname.substring(1).tolower()
        $Lastname = $Lastname.substring(0,1).toupper() + $Lastname.substring(1).tolower()
        $Email = $Email.tolower()
        $Address = $Address.substring(0,1).toupper() + $Address.substring(1).tolower()
        $City = $City.substring(0,1).toupper() + $City.substring(1).tolower()
        $Country = $Country.substring(0,1).toupper() + $Country.substring(1).tolower()

        $q = "INSERT INTO Users (Firstname,Lastname,Email,Address,Postalcode,City,Country,Birthday) 
        VALUES ('$Firstname','$Lastname','$Email','$Address','$Postalcode','$City','$Country','$Birthday')"

        $insert = Invoke-MySQLQuery -Query $q

        if($insert.Status)
        {
            $q = "INSERT INTO Login (UserID,Hash,Salt) 
            VALUES ($($insert.LastInsertedID),'$Hash','$Salt')"

            $insert = Invoke-MySQLQuery -Query $q
        }

        return [pscustomobject]@{
            Status = $true
            Message = "User '$($Firstname) $($Lastname)' created successfully"
        }
    }
    catch
    {
        return [pscustomobject]@{
            Status = $false
            Message = $($_.exception.message)
        }
        
    }
}

function Add-NewUser
{
    switch (Invoke-Prompt -Title 'New user' -Message 'Do you want to create a new user?')
        {
            0 {
                $p = [pscustomobject]@{

                    Firstname = Read-Host "Firstname"
                    Lastname = Read-Host "Lastname"
                    Email = Read-Host "Email"
                    Address = Read-Host "Address"
                    Postalcode = Read-Host "Postalcode"
                    City = Read-Host "City"
                    Country = Read-Host "Country"
                    BD = Read-Host "Date of birth (dd.mm.yyyy)"
                    PW = Prompt-Password -AsHash
                }

                $adder = Add-UserToDB -Firstname $p.Firstname -Lastname $p.Lastname -Email $p.Email -Address $p.Address -Postalcode $p.Postalcode -City $p.City -Country $p.Country -Hash $p.PW.Hash -Salt $p.PW.Salt

                return $adder.message     
            }

            1
            {
                return "Creating a new user canceled"
            }
        }
}

function Invoke-Prompt
{
param(
$Options = ('Yes','No'),
$Title = "Stamps",
$Message = "Select option"
)
    $opt = $options | % {
        New-Object System.Management.Automation.Host.ChoiceDescription "&$_", $_
    }

    return $host.ui.PromptForChoice($Title, $Message, $opt, 0) 
}

function Get-Discount
{
param($CompanyID)

    $q = "SELECT DiscountID,DiscountName,Description FROM Discount WHERE CompanyID = $CompanyID"
    return Invoke-MySQLQuery -Query $q
}

function Invoke-GiveStamp
{
param($CompanyID)

    Write-Output "Select Discount"
    $discount = (Get-Discount -CompanyID $CompanyID).data | Out-GridView -PassThru

    do
    {
        $CustomerID = [Microsoft.VisualBasic.Interaction]::InputBox("Enter a Customer ID", "Give stamp to customer", "") 
        $userFind = Get-UserFromDB -Filter "UserID = $CustomerID"
    }
    until($userFind.Data.UserID)
    Write-Output "User found"
    #$userFind.data  | Out-GridView -PassThru

    if(!(Invoke-Prompt -Title 'Give Stamp' -Message "Give Stamp to user '$($userFind.data.FirstName) $($userFind.data.LastName)' ID: $($userFind.data.UserID)"))
    {
        Add-StampToCustomer -DiscountID $discount.DiscountID -CustomerID $userFind.Data.UserID
        Write-Output "Stamp Added"
    }
    else
    {
        Write-Output "Action Canceled"
    }
}

function Invoke-CreateDiscount
{
param($CompanyID)

    return "Invoke-CreateDiscount $CompanyID"
}

function Invoke-DeleteDiscount
{
param($CompanyID)

    return "Invoke-DeleteDiscount $CompanyID"
}

function Invoke-StampsAction
{
param($User)
    $exit = $false
    while(!$exit)
    {
        $User = Get-UserFromDB -filter "UserID = $($User.Data.UserID)"

        if($User.Data.IsCompanyAccount) # company
        {
            $actions = '1.Give Stamp','2.Create Discount','3.Delete Discount','4.Change Password','5.Logout'

            switch (Invoke-Prompt -Options $actions)
            {
                0 # Give Stamp
                {
                    cls
                    Print-Logo -Version $version
                    Invoke-GiveStamp -CompanyID $User.Data.CompanyID          
                }

                1 # Create Discount
                {
                    cls
                    Print-Logo -Version $version
                    Invoke-CreateDiscount -CompanyID $User.Data.CompanyID              
                }

                2 # Delete Discount
                {
                    cls
                    Print-Logo -Version $version
                    Invoke-DeleteDiscount -CompanyID $User.Data.CompanyID              
                }

                3 # Change Password
                {
                    $pinAction = New-PIN -ID $User.ID
                    $pinAction.message
                }

                4 # Logout
                {
                    Write-Output 'Logout successfully'
                    $exit = $true
                }

            }

        
        }
        else # customer
        {
            $actions = '1.Get Stamps','2.Change Password PIN','3.Logout'

            switch (Invoke-Prompt -Options $actions)
            {
                0 # Get stamps
                                                    {
                cls
                Print-Logo -Version $version          
                Write-Output "User: $($user.data.FirstName) $($user.data.LastName) ID: $($user.data.UserID)"
                [environment]::NewLine
                Write-Output "Stamps:"
                
                (Get-Stamps -UserID $User.data.UserID).data | Format-Table | Out-String
                   
            }

                1 # Password change
                            {
                $pinAction = New-PIN -ID $User.ID
                $pinAction.message
            }

                2 # logout
                            {
                Write-Output 'Logout successfully'
                $exit = $true
            }

            }
        }
    }
}

while(!$exit)
{
    cls
    sleep -Milliseconds 100
    Print-Logo -Version $version
    sleep -Milliseconds 100

    switch(Invoke-Prompt -Options '1.Login','2.Register','3.Exit')
    {  
        0 # Login
        {
            $r = Read-Host "Enter email address to login"

            if(Test-PW -Username $r -Password (Prompt-Password))
            {
                Write-Output "Login successfull"
                Read-Host '[PRESS ENTER]'
                Invoke-StampsAction -User (Get-UserFromDB -filter "Email = '$r'")
            }
            else
            {
                Write-Output 'Login failed'
                Read-Host
            }
        }

        1 # register
        {
            Add-NewUser
            Read-Host
        }

        2 # Exit
        {
            $exit = $true
        }
    }

    if($exit)
    {
        Write-Output 'Stamps application closed'
        break
    }

} # Main loop ends
