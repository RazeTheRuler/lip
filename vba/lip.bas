Attribute VB_Name = "lip"

Option Explicit

'Lundalogik Package Store, DO NOT CHANGE, used to download system files for LIP
'Please add your own stores in packages.json
Private Const BaseURL As String = "http://api.lime-bootstrap.com"
Private Const ApiURL As String = "/packages/"

Private Const DefaultInstallPath = "packages\"

Private IndentLenght As String
Private Indent As String
Private sLog As String
Private sSimulateMsg As String

Public Sub UpgradePackage(Optional PackageName As String, Optional Path As String)
On Error GoTo Errorhandler:
    If PackageName = "" Then
        'Upgrade all packages
        Call InstallFromPackageFile
    Else
        'Upgrade specific package
        Call Install(PackageName, True)
    End If
Exit Sub
Errorhandler:
    Call UI.ShowError("lip.UpgradePackage")
End Sub

'Install package/app. Selects packagestore from packages.json
Public Sub Install(PackageName As String, Optional Upgrade As Boolean, Optional Simulate As Boolean = True)
On Error GoTo Errorhandler
    Dim Package As Object
    Dim PackageVersion As Double
    Dim downloadURL As String
    Dim InstallPath As String

    IndentLenght = "  "
    
    sLog = ""

    'Check if first use ever
    If Dir(WebFolder + "packages.json") = "" Then
        sLog = sLog + Indent + "No packages.json found, assuming fresh install" + vbNewLine
        Call InstallLIP
    End If

    PackageName = LCase(PackageName)

    sLog = sLog + Indent + "====== LIP Install: " + PackageName + " ======" + vbNewLine

    sLog = sLog + Indent + "Looking for package: '" + PackageName + "'" + vbNewLine
    Set Package = SearchForPackageOnStores(PackageName)
    If Package Is Nothing Then
        Exit Sub
    End If

    If Package.Exists("source") Then
        downloadURL = VBA.Replace(Package.Item("source"), "\/", "/") 'Replace \/ with only / since JSON escapes frontslash with a backslash which causes problems with URLs
    Else
        downloadURL = BaseURL & ApiURL & PackageName & "/download/"  'Use Lundalogik Packagestore if source-node wasn't found
    End If

    If Package.Exists("installPath") Then
        InstallPath = ThisApplication.WebFolder & Package.Item("installPath") & "\"
    Else
        InstallPath = ThisApplication.WebFolder & DefaultInstallPath
    End If

    Set Package = Package

    'Parse result from store
    PackageVersion = findNewestVersion(Package.Item("versions"))

    'Check if package already exsists
    If Not Upgrade Then
        If CheckForLocalInstalledPackage(PackageName, PackageVersion) = True Then
            Call Lime.MessageBox("Package already installed. If you want to upgrade the package, run command: " & vbNewLine & vbNewLine & "Call lip.Install(""" & PackageName & """, True)", vbInformation)
            Exit Sub
        End If
    End If

    'Install dependecies
    If Package.Exists("dependencies") Then
        IncreaseIndent
        Call InstallDependencies(Package, Simulate)
        DecreaseIndent
    End If

    'Download and unzip
    sLog = sLog + Indent + "Downloading '" + PackageName + "' files..." + vbNewLine

    Call DownloadFile(PackageName, downloadURL, InstallPath)
    Call Unzip(PackageName, InstallPath)
    sLog = sLog + Indent + "Download complete!" + vbNewLine

    Call InstallPackageComponents(PackageName, PackageVersion, Package, InstallPath, Simulate)

    sLog = sLog + Indent + "===================================" + vbNewLine
    
    If Simulate Then
        If vbYes = Lime.MessageBox("Simulation of installation process completed. Below you find the result. Do you wish to proceed with the installation?" & vbNewLine & vbNewLine & sLog, vbInformation + vbYesNo + vbDefaultButton2) Then
            Call lip.Install(PackageName, Upgrade, False)
        End If
    Else
        Dim sLogfile As String
        sLogfile = Application.TemporaryFolder & "\" & PackageName & VBA.Replace(VBA.Replace(VBA.Replace(VBA.Now(), ":", ""), "-", ""), " ", "") & ".txt"
        Open sLogfile For Output As #1
        Print #1, sLog
        Close #1
        
        If vbYes = Lime.MessageBox("Installation process completed. Do you want to open the logfile for the installation?", vbInformation + vbYesNo + vbDefaultButton1) Then
            ThisApplication.Shell (sLogfile)
        Else
            Debug.Print ("Logfile is available here: " & sLogfile)
        End If
    End If
    
    sLog = ""

Exit Sub
Errorhandler:
    Call UI.ShowError("lip.Install")
End Sub

'Installs package from a zip-file. Input parameter: complete searchpath to the zip-file, including the filename
Public Sub InstallFromZip(ZipPath As String, Optional Simulate As Boolean = True)
On Error GoTo Errorhandler

    sLog = ""

    'Check if valid path
    If VBA.Right(ZipPath, 4) = ".zip" Then
        If VBA.Dir(ZipPath) <> "" Then
            'Check if first use ever
            If Dir(WebFolder + "packages.json") = "" Then
                sLog = sLog + Indent + "No packages.json found, assuming fresh install" + vbNewLine
                Call InstallLIP
            End If

'           Copy file to actionpads\apps
            Dim PackageName As String
            Dim strArray() As String
            strArray = VBA.Split(ZipPath, "\")
            PackageName = VBA.Split(strArray(UBound(strArray)), ".")(0)
            sLog = sLog + Indent + "====== LIP Install: " + PackageName + " ======" + vbNewLine
            sLog = sLog + Indent + "Copying and unzipping file" + vbNewLine

            'Copy zip-file to the apps-folder if it's not already there
            If ZipPath <> ThisApplication.WebFolder & "apps\" & PackageName & ".zip" Then
                Call VBA.FileCopy(ZipPath, ThisApplication.WebFolder & DefaultInstallPath & PackageName & ".zip")
            End If

'           Unzip file
            Call Unzip(PackageName, ThisApplication.WebFolder & DefaultInstallPath) 'Filename without fileextension as parameter

            'Get package information from json-file
            Dim Package As Object
            Dim sJSON As String
            Dim sLine As String
    
            'Look for package.json or app.json
            If VBA.Dir(ThisApplication.WebFolder & DefaultInstallPath & PackageName & "\" & "package.json") <> "" Then
                Open ThisApplication.WebFolder & DefaultInstallPath & PackageName & "\" & "package.json" For Input As #1
                
            ElseIf VBA.Dir(ThisApplication.WebFolder & DefaultInstallPath & PackageName & "\" & "app.json") <> "" Then
                Open ThisApplication.WebFolder & DefaultInstallPath & PackageName & "\" & "app.json" For Input As #1
                
            Else
                sLog = sLog + (Indent + "Installation failed: couldn't find any package.json or app.json in the zip-file") + vbNewLine
                Exit Sub
            End If

            Do Until EOF(1)
                Line Input #1, sLine
                sJSON = sJSON & sLine
            Loop

            Close #1

            Set Package = JSON.parse(sJSON)

            'Install dependencies
            If Package.Exists("dependencies") Then
                IncreaseIndent
                Call InstallDependencies(Package, Simulate)
                DecreaseIndent
            End If

            Call InstallPackageComponents(PackageName, 1, Package, ThisApplication.WebFolder & DefaultInstallPath, Simulate)

            sLog = sLog + Indent + "===================================" + vbNewLine
            
            If Simulate Then
                If vbYes = Lime.MessageBox("Simulation of installation process completed. Below you find the result. Do you wish to proceed with the installation?" & vbNewLine & vbNewLine & sLog, vbInformation + vbYesNo + vbDefaultButton2) Then
                    Call lip.InstallFromZip(ZipPath, False)
                End If
            Else
                Dim sLogfile As String
                sLogfile = Application.TemporaryFolder & "\" & PackageName & VBA.Replace(VBA.Replace(VBA.Replace(VBA.Now(), ":", ""), "-", ""), " ", "") & ".txt"
                Open sLogfile For Output As #1
                Print #1, sLog
                Close #1
                
                If vbYes = Lime.MessageBox("Installation process completed. Do you want to open the logfile for the installation?", vbInformation + vbYesNo + vbDefaultButton1) Then
                    ThisApplication.Shell (sLogfile)
                Else
                    Debug.Print ("Logfile is available here: " & sLogfile)
                End If
            End If
        Else
            Call Lime.MessageBox("Couldn't find file.")
        End If
    Else
        Call Lime.MessageBox("Path must end with .zip")
    End If
    
    sLog = ""

Exit Sub
Errorhandler:
    Call UI.ShowError("lip.InstallFromZip")
End Sub

'Installs all packages defined in the packages.json file
Public Sub InstallFromPackageFile()
On Error GoTo Errorhandler
    Dim LocalPackages As Object
    Dim LocalPackageName As Variant

    sLog = sLog + Indent + "Installing dependecies from packages.json file..." + vbNewLine
    Set LocalPackages = ReadPackageFile().Item("dependencies")
    If LocalPackages Is Nothing Then
        Exit Sub
    End If
    For Each LocalPackageName In LocalPackages.keys
        Call Install(CStr(LocalPackageName), True)
    Next LocalPackageName
Exit Sub
Errorhandler:
    Call UI.ShowError("lip.InstallFromPackageFile")
End Sub


Private Sub InstallPackageComponents(PackageName As String, PackageVersion As Double, Package, InstallPath As String, Simulate As Boolean)
On Error GoTo Errorhandler
    
    Dim bOk As Boolean
    bOk = True

    'Install localizations
    If Package.Item("install").Exists("localize") = True Then
        sLog = sLog + Indent + "Adding localizations..." + vbNewLine
        IncreaseIndent
        If InstallLocalize(Package.Item("install").Item("localize"), Simulate) = False Then
            bOk = False
        End If
        DecreaseIndent

    End If

    'Install VBA
    If Package.Item("install").Exists("vba") = True Then
        sLog = sLog + Indent + "Adding VBA modules, forms and classes..." + vbNewLine
        IncreaseIndent
        If InstallVBAComponents(PackageName, Package.Item("install").Item("vba"), InstallPath, Simulate) = False Then
            bOk = False
        End If
        DecreaseIndent
    End If

    If Package.Item("install").Exists("tables") = True Then
        IncreaseIndent
        If InstallFieldsAndTables(Package.Item("install").Item("tables"), Simulate) = False Then
            bOk = False
        End If
        DecreaseIndent
    End If
    
    If Package.Item("install").Exists("relations") = True Then
        IncreaseIndent
        If InstallRelations(Package.Item("install").Item("relations"), Simulate) = False Then
            bOk = False
        End If
        DecreaseIndent
    End If

'    If Package.Item("install").Exists("sql") = True Then
'        IncreaseIndent
'        If InstallSQL(Package.Item("install").Item("sql"), PackageName, InstallPath, Simulate) = False Then
'            bOk = False
'        End If
'        DecreaseIndent
'    End If

    If Package.Item("install").Exists("files") = True Then
        IncreaseIndent
        If InstallFiles(Package.Item("install").Item("files"), PackageName, InstallPath, Simulate) = False Then
            bOk = False
        End If
        DecreaseIndent
    End If
    'Update packages.json
    If WriteToPackageFile(PackageName, CStr(PackageVersion), Simulate) = False Then
        bOk = False
    End If
    
    If bOk Then
        sLog = sLog + Indent + "Installation of " + PackageName + " done!" + vbNewLine
    Else
        sLog = sLog + Indent + "Something went wrong while installing " + PackageName + ". Please check for error messages above." + vbNewLine
    End If
Exit Sub
Errorhandler:
    Call UI.ShowError("lip.InstallPackageComponents")
End Sub

Private Sub InstallDependencies(Package As Object, Simulate As Boolean)
On Error GoTo Errorhandler
    Dim DependencyName As Variant
    Dim LocalPackage As Object
    sLog = sLog + Indent + "Dependencies found! Installing..." + vbNewLine
    IncreaseIndent
    For Each DependencyName In Package.Item("dependencies").keys()
        Set LocalPackage = FindPackageLocally(CStr(DependencyName))
        If LocalPackage Is Nothing Then
            sLog = sLog + Indent + "Installing dependency: " + CStr(DependencyName) + vbNewLine
            Call Install(CStr(DependencyName), Simulate)
        ElseIf CDbl(VBA.Replace(LocalPackage.Item(DependencyName), ".", ",")) < CDbl(VBA.Replace(Package.Item("dependencies").Item(DependencyName), ".", ",")) Then
            Call Install(CStr(DependencyName), True, Simulate)
        Else
        End If
    Next DependencyName
    Call DecreaseIndent
Exit Sub
Errorhandler:
    Call UI.ShowError("lip.InstallDependencies")
End Sub


Private Function SearchForPackageOnStores(PackageName As String) As Object
On Error GoTo Errorhandler
    Dim sJSON As String
    Dim oJSON As Object
    Dim oPackages As Object
    Dim Path As String
    Dim oPackage As Variant

    Set oPackages = ReadPackageFile.Item("stores")

    'Loop through packagestores from packages.json
    For Each oPackage In oPackages

        Path = oPackages.Item(oPackage)
        sLog = sLog + Indent + ("Looking for package at store '" & oPackage & "'") + vbNewLine
        sJSON = getJSON(Path + PackageName + "/")

        If sJSON <> "" Then
            sJSON = VBA.Left(sJSON, VBA.Len(sJSON) - 1) & ",""source"":""" & oPackages.Item(oPackage) & """}" 'Add a source node so we know where the package exists
        End If

        Set oJSON = parseJSON(sJSON) 'Create a JSON object from the string

        If Not oJSON Is Nothing Then
            If oJSON.Item("error") = "" Then
                'Package found, make sure the install node exists
                If Not oJSON.Item("install") Is Nothing Then
                    sLog = sLog + Indent + ("Package '" & PackageName & "' found on store '" & oPackage & "'") + vbNewLine
                    Set SearchForPackageOnStores = oJSON
                    Exit Function
                Else
                    sLog = sLog + Indent + ("Package '" & PackageName & "' found on store '" & oPackage & "' but has no valid install instructions!") + vbNewLine
                    Set SearchForPackageOnStores = Nothing
                    Exit Function
                End If
            End If
        End If
    Next

    'If we've reached this code, package wasn't found
    sLog = sLog + Indent + ("Package '" & PackageName & "' not found!") + vbNewLine
    Set SearchForPackageOnStores = Nothing

Exit Function
Errorhandler:
    Set SearchForPackageOnStores = Nothing
    Call UI.ShowError("lip.SearchForPackageOnStores")
End Function

Private Function CheckForLocalInstalledPackage(PackageName As String, PackageVersion As Double) As Boolean
On Error GoTo Errorhandler
    Dim LocalPackages As Object
    Dim LocalPackage As Object
    Dim LocalPackageVersion As Double
    Dim LocalPackageName As Variant

    Set LocalPackage = FindPackageLocally(PackageName)

    If Not LocalPackage Is Nothing Then
        LocalPackageVersion = CDbl(VBA.Replace(LocalPackage.Item(PackageName), ".", ","))
        If PackageVersion = LocalPackageVersion Then
            sLog = sLog + Indent + "Current version of" + PackageName + " is already installed, please use the upgrade command to reinstall package" + vbNewLine
            sLog = sLog + Indent + "===================================" + vbNewLine
            CheckForLocalInstalledPackage = True
            Exit Function
        ElseIf PackageVersion > LocalPackageVersion Then
            sLog = sLog + Indent + "Package " + PackageName + " is already installed, please use the upgrade command to upgrade package from " + Format(LocalPackageVersion, "0.0") + " -> " + Format(PackageVersion, "0.0") + vbNewLine
            sLog = sLog + Indent + "===================================" + vbNewLine
            CheckForLocalInstalledPackage = True
            Exit Function
        Else
            sLog = sLog + Indent + "A newer version of " + PackageName + " is already installed. Remote: " + Format(PackageVersion, "0.0") + " ,Local: " + Format(LocalPackageVersion, "0.0") + ". Please use the upgrade command to reinstall package" + vbNewLine
            sLog = sLog + Indent + "===================================" + vbNewLine
            CheckForLocalInstalledPackage = True
            Exit Function
        End If
    End If
    CheckForLocalInstalledPackage = False
Exit Function
Errorhandler:
    Call UI.ShowError("lip.CheckForLocalInstalledPackages")
End Function

Private Function getJSON(sURL As String) As String
On Error GoTo Errorhandler
    Dim qs As String
    qs = CStr(Rnd() * 1000000#)
    Dim oXHTTP As Object
    Dim s As String
    Set oXHTTP = CreateObject("MSXML2.XMLHTTP")
    oXHTTP.Open "GET", sURL + "?" + qs, False
    oXHTTP.Send
    getJSON = oXHTTP.responseText
Exit Function
Errorhandler:
    getJSON = ""
End Function

Private Function parseJSON(sJSON As String) As Object
On Error GoTo Errorhandler
    Dim oJSON As Object
    Set oJSON = JSON.parse(sJSON)
    Set parseJSON = oJSON
Exit Function
Errorhandler:
    Set parseJSON = Nothing
    Call UI.ShowError("lip.parseJSON")
End Function

Private Function findNewestVersion(oVersions As Object) As Double
On Error GoTo Errorhandler
    Dim NewestVersion As Double
    Dim Version As Variant
    NewestVersion = -1

    For Each Version In oVersions
        If CDbl(VBA.Replace(Version.Item("version"), ".", ",")) > NewestVersion Then
            NewestVersion = CDbl(VBA.Replace(Version.Item("version"), ".", ","))
        End If
    Next Version
    findNewestVersion = NewestVersion
Exit Function
Errorhandler:
    findNewestVersion = -1
    Call UI.ShowError("lip.findNewestVersion")
End Function

Private Function InstallLocalize(oJSON As Object, Simulate As Boolean) As Boolean
On Error GoTo Errorhandler
    Dim bOk As Boolean
    Dim Localize As Variant
    bOk = True
    
    For Each Localize In oJSON
        If AddOrCheckLocalize( _
            Localize.Item("owner"), _
            Localize.Item("context"), _
            "", _
            Localize.Item("en_us"), _
            Localize.Item("sv"), _
            Localize.Item("no"), _
            Localize.Item("fi"), _
            Simulate _
        ) = False Then
            bOk = False
        End If
    Next Localize
    
    InstallLocalize = bOk
    
Exit Function
Errorhandler:
    InstallLocalize = False
    Call UI.ShowError("lip.InstallLocalize")
End Function

Private Function InstallFiles(oJSON As Object, PackageName As String, InstallPath As String, Simulate As Boolean) As Boolean
On Error GoTo Errorhandler
    Dim bOk As Boolean
    Dim FSO As Object
    Dim FromPath As String
    Dim ToPath As String
    Dim File As Variant
    
    bOk = True

    For Each File In oJSON
        FromPath = InstallPath & PackageName & "\" & File
        ToPath = WebFolder & File

        If Right(FromPath, 1) = "\" Then
            FromPath = Left(FromPath, Len(FromPath) - 1)
        End If
        If Right(ToPath, 1) = "\" Then
            ToPath = Left(ToPath, Len(ToPath) - 1)
        End If
        Set FSO = CreateObject("scripting.filesystemobject")

        FSO.CopyFolder Source:=FromPath, Destination:=ToPath
        On Error Resume Next 'It is a beautiful languge
        If Simulate Then
            VBA.Kill ToPath
        Else
            VBA.Kill FromPath
        End If
        On Error GoTo Errorhandler
    Next File
    
    InstallFiles = bOk

Errorhandler:
    InstallFiles = False
    Call UI.ShowError("lip.InstallFiles")
End Function

'Private Function InstallSQL(oJSON As Object, PackageName As String, InstallPath As String) As Boolean
'On Error GoTo ErrorHandler
'    Dim bOk As Boolean
'    Dim SQL As Variant
'    Dim Path As String
'    Dim RelPath As String
'
'    bOk = True
'
'    slog=slog+ Indent + "Installing SQL..." +vbnewline
'    IncreaseIndent
'    For Each SQL In oJSON
'        RelPath = Replace(SQL.Item("relPath"), "/", "\")
'        Path = InstallPath & PackageName & "\" & RelPath
'        If CreateSQLProcedure(Path, SQL.Item("name"), SQL.Item("type")) = False Then
'            bOk = False
'        End If
'    Next SQL
'    DecreaseIndent
'    InstallSQL = bOk
'Exit Function
'ErrorHandler:
'    InstallSQL = False
'    Call UI.ShowError("lip.InstallSQL")
'End Function
'
'Private Function CreateSQLProcedure(Path As String, Name As String, ProcType As String) As Boolean
'    Dim bOk As Boolean
'    Dim oProc As New LDE.Procedure
'    Dim strSQL As String
'    Dim sLine As String
'    Dim sErrormessage As String
'
'    bOk = True
'    strSQL = ""
'    sErrormessage = ""
'
'    Open Path For Input As #1
'        Do Until EOF(1)
'            Line Input #1, sLine
'            strSQL = strSQL & sLine & vbNewLine
'        Loop
'        Close #1
'
'        Set oProc = Database.Procedures("csp_lip_installSQL")
'        If Not oProc Is Nothing Then
'            oProc.Parameters("@@sql") = strSQL
'            oProc.Parameters("@@name") = Name
'            oProc.Parameters("@@type") = ProcType
'            oProc.Execute (False)
'
'            sErrormessage = oProc.Parameters("@@errormessage").OutputValue
'
'            If sErrormessage <> "" Then
'                slog=slog+ Indent + (sErrormessage)+vbnewline
'                bOk = False
'            Else
'                slog=slog+ Indent + ("'" & Name & "'" & " added.")+vbnewline
'            End If
'
'        Else
'            bOk = False
'            Call Lime.MessageBox("Couldn't find SQL-procedure 'csp_lip_installSQL'. Please make sure this procedure exists in the database and restart LDC.")
'        End If
'
'        CreateSQLProcedure = bOk
'
'Exit Function
'ErrorHandler:
'    CreateSQLProcedure = False
'    Call UI.ShowError("lip.CreateSQLProcedure")
'End Function

Private Function InstallFieldsAndTables(oJSON As Object, Simulate As Boolean) As Boolean
On Error GoTo Errorhandler
    Dim bOk As Boolean
    Dim table As Object
    Dim oProc As LDE.Procedure
    Dim field As Object
    Dim idtable As Long
    Dim iddescriptiveexpression As Long
    Dim oItem As Variant

    Dim localname_singular As String
    Dim localname_plural As String
    Dim errormessage As String
    
    bOk = True

    sLog = sLog + Indent + "Adding fields and tables..." + vbNewLine
    IncreaseIndent

    For Each table In oJSON
        localname_singular = ""
        localname_plural = ""
        errormessage = ""

        Set oProc = Database.Procedures("csp_lip_createtable")

        If Not oProc Is Nothing Then

            sLog = sLog + Indent + "Add table: " + table.Item("name") + vbNewLine

            oProc.Parameters("@@tablename").InputValue = table.Item("name")
            oProc.Parameters("@@simulate").InputValue = Simulate

            'Add localnames singular
            If table.Exists("localname_singular") Then
                For Each oItem In table.Item("localname_singular")
                    If oItem <> "" Then
                        localname_singular = localname_singular + VBA.Trim(oItem) + ":" + VBA.Trim(table.Item("localname_singular").Item(oItem)) + ";"
                    End If
                Next
                oProc.Parameters("@@localname_singular").InputValue = localname_singular
            End If

            'Add localnames plural
            If table.Exists("localname_plural") Then
                For Each oItem In table.Item("localname_plural")
                    If oItem <> "" Then
                        localname_plural = localname_plural + VBA.Trim(oItem) + ":" + VBA.Trim(table.Item("localname_plural").Item(oItem)) + ";"
                    End If
                Next
                oProc.Parameters("@@localname_plural").InputValue = localname_plural
            End If

            Call oProc.Execute(False)

            errormessage = oProc.Parameters("@@errorMessage").OutputValue

            idtable = oProc.Parameters("@@idtable").OutputValue
            iddescriptiveexpression = oProc.Parameters("@@iddescriptiveexpression").OutputValue

            'If errormessage is set, something went wrong
            If errormessage <> "" Then
                sLog = sLog + Indent + (errormessage) + vbNewLine
                bOk = False
            Else
                sLog = sLog + Indent + ("Table """ & table.Item("name") & """ created.") + vbNewLine
            End If

            ' Create fields
            IncreaseIndent
            If table.Exists("fields") Then
                For Each field In table.Item("fields")
                    sLog = sLog + Indent + "Add field: " + field.Item("name") + vbNewLine
                    If AddField(table.Item("name"), field, Simulate) = False Then
                        bOk = False
                    End If
                Next field
            End If

            'Set table attributes(must be done AFTER fields has been created in order to be able to set descriptive expression)
            'Only set attributes if table was created
            If idtable <> -1 Then
                If SetTableAttributes(table, idtable, iddescriptiveexpression, Simulate) = False Then
                    bOk = False
                End If
            End If

            DecreaseIndent

        Else
            bOk = False
            Call Lime.MessageBox("Couldn't find SQL-procedure 'csp_lip_createtable'. Please make sure this procedure exists in the database and restart LDC.")
        End If

    Next table
    DecreaseIndent

    Set oProc = Nothing
    
    InstallFieldsAndTables = bOk

    Exit Function
Errorhandler:
    Set oProc = Nothing
    InstallFieldsAndTables = False
    Call UI.ShowError("lip.InstallFieldsAndTables")
End Function


Private Function AddField(tableName As String, field As Object, Simulate As Boolean) As Boolean
On Error GoTo Errorhandler
    Dim bOk As Boolean
    Dim oProc As New LDE.Procedure
    Dim errormessage As String
    Dim fieldLocalnames As String
    Dim separatorLocalnames As String
    Dim limevalidationtextLocalnames As String
    Dim commentLocalnames As String
    Dim tooltipLocalnames As String
    Dim oItem As Variant
    Dim optionItems As Variant
    bOk = True
    errormessage = ""
    fieldLocalnames = ""
    separatorLocalnames = ""
    limevalidationtextLocalnames = ""
    commentLocalnames = ""
    tooltipLocalnames = ""
    
    Set oProc = Database.Procedures("csp_lip_createfield")

    If Not oProc Is Nothing Then
        oProc.Parameters("@@tablename").InputValue = tableName
        oProc.Parameters("@@fieldname").InputValue = field.Item("name")
        oProc.Parameters("@@simulate").InputValue = Simulate

        'Add localnames
        If field.Exists("localname") Then
            For Each oItem In field.Item("localname")
                If oItem <> "" Then
                    fieldLocalnames = fieldLocalnames + VBA.Trim(oItem) + ":" + VBA.Trim(field.Item("localname").Item(oItem)) + ";"
                End If
            Next
            oProc.Parameters("@@localname").InputValue = fieldLocalnames
        End If

        'Add attributes
        If field.Exists("attributes") Then
            For Each oItem In field.Item("attributes")
                If oItem <> "" Then
                    If Not oProc.Parameters.Lookup("@@" & oItem, lkLookupProcedureParameterByName) Is Nothing Then
                        oProc.Parameters("@@" & oItem).InputValue = field.Item("attributes").Item(oItem)
                    Else
                        sLog = sLog + Indent + ("No support for setting field attribute " & oItem) + vbNewLine
                    End If
                End If
            Next
        End If

        'Add separator
        If field.Exists("separator") Then
            For Each oItem In field.Item("separator")
                separatorLocalnames = separatorLocalnames + VBA.Trim(oItem) + ":" + VBA.Trim(field.Item("separator").Item(oItem)) + ";"
            Next
            oProc.Parameters("@@separator").InputValue = separatorLocalnames
        End If
        
        'Add limevalidationtext
        If field.Exists("limevalidationtext") Then
            For Each oItem In field.Item("limevalidationtext")
                limevalidationtextLocalnames = limevalidationtextLocalnames + VBA.Trim(oItem) + ":" + VBA.Trim(field.Item("limevalidationtext").Item(oItem)) + ";"
            Next
            oProc.Parameters("@@limevalidationtext").InputValue = limevalidationtextLocalnames
        End If
        
        'Add comment
        If field.Exists("comment") Then
            For Each oItem In field.Item("comment")
                commentLocalnames = commentLocalnames + VBA.Trim(oItem) + ":" + VBA.Trim(field.Item("comment").Item(oItem)) + ";"
            Next
            oProc.Parameters("@@comment").InputValue = commentLocalnames
        End If
        
        'Add tooltip (description)
        If field.Exists("description") Then
            For Each oItem In field.Item("description")
                tooltipLocalnames = tooltipLocalnames + VBA.Trim(oItem) + ":" + VBA.Trim(field.Item("description").Item(oItem)) + ";"
            Next
            oProc.Parameters("@@description").InputValue = tooltipLocalnames
        End If

        Dim strOptions As String
        strOptions = ""
        'Add options
        If field.Exists("options") Then
            For Each optionItems In field.Item("options")
                strOptions = strOptions + "["
                For Each oItem In optionItems
                    strOptions = strOptions + VBA.Trim(oItem) + ":" + VBA.Trim(optionItems.Item(oItem)) + ";"
                Next
                strOptions = strOptions + "]"
            Next
            oProc.Parameters("@@optionlist").InputValue = strOptions
        End If

        Call oProc.Execute(False)
        errormessage = oProc.Parameters("@@errorMessage").OutputValue

        'If errormessage is set, something went wrong
        If errormessage <> "" Then
            sLog = sLog + Indent + (errormessage) + vbNewLine
            bOk = False
        Else
            sLog = sLog + Indent + ("Field """ & field.Item("name") & """ created.") + vbNewLine
        End If
    Else
        bOk = False
        Call Lime.MessageBox("Couldn't find SQL-procedure 'csp_lip_createfield'. Please make sure this procedure exists in the database and restart LDC.")
    End If
    Set oProc = Nothing
    AddField = bOk

    Exit Function
Errorhandler:
    Set oProc = Nothing
    AddField = False
    Call UI.ShowError("lip.AddField")
End Function

Private Function SetTableAttributes(ByRef table As Object, idtable As Long, iddescriptiveexpression As Long, Simulate As Boolean) As Boolean
On Error GoTo Errorhandler

    Dim bOk As Boolean
    Dim oProcAttributes As LDE.Procedure
    Dim oItem As Variant
    Dim errormessage As String
    
    bOk = True

    If table.Exists("attributes") Then

        Set oProcAttributes = Application.Database.Procedures("csp_lip_settableattributes")

        If Not oProcAttributes Is Nothing Then

            sLog = sLog + Indent + "Adding attributes for table: " + table.Item("name") + vbNewLine

            oProcAttributes.Parameters("@@tablename").InputValue = table.Item("name")
            oProcAttributes.Parameters("@@idtable").InputValue = idtable
            oProcAttributes.Parameters("@@iddescriptiveexpression").InputValue = iddescriptiveexpression
            oProcAttributes.Parameters("@@simulate").InputValue = Simulate

            For Each oItem In table.Item("attributes")
                If oItem <> "" Then
                    If Not oProcAttributes.Parameters.Lookup("@@" & oItem, lkLookupProcedureParameterByName) Is Nothing Then
                        oProcAttributes.Parameters("@@" & oItem).InputValue = table.Item("attributes").Item(oItem)
                    Else
                        sLog = sLog + Indent + ("No support for setting table attribute " & oItem) + vbNewLine
                    End If
                End If
            Next

            Call oProcAttributes.Execute(False)

            errormessage = oProcAttributes.Parameters("@@errorMessage").OutputValue

            'If errormessage is set, something went wrong
            If errormessage <> "" Then
                sLog = sLog + Indent + (errormessage) + vbNewLine
                bOk = False
            Else
                sLog = sLog + Indent + ("Attributes for table """ & table.Item("name") & """ set.") + vbNewLine
            End If

        Else
            bOk = False
            Call Lime.MessageBox("Couldn't find SQL-procedure 'csp_lip_settableattributes'. Please make sure this procedure exists in the database and restart LDC.")
        End If
    End If

    Set oProcAttributes = Nothing
    
    SetTableAttributes = bOk

    Exit Function
Errorhandler:
    Set oProcAttributes = Nothing
    SetTableAttributes = False
    Call UI.ShowError("lip.SetTableAttributes")
End Function

Private Sub DownloadFile(PackageName As String, Path As String, InstallPath As String)
On Error GoTo Errorhandler
    Dim qs As String
    qs = CStr(Rnd() * 1000000#)
    Dim downloadURL As String
    Dim myURL As String
    Dim oStream As Object
    downloadURL = Path + PackageName + "/download/"

    Dim WinHttpReq As Object
    Set WinHttpReq = CreateObject("Microsoft.XMLHTTP")
    WinHttpReq.Open "GET", downloadURL + "?" + qs, False
    WinHttpReq.Send

    myURL = WinHttpReq.responseBody
    If WinHttpReq.status = 200 Then
        Set oStream = CreateObject("ADODB.Stream")
        oStream.Open
        oStream.Type = 1
        oStream.Write WinHttpReq.responseBody
        oStream.SaveToFile InstallPath + PackageName + ".zip", 2 ' 1 = no overwrite, 2 = overwrite
        oStream.Close
    End If
    Exit Sub
Errorhandler:
    Call UI.ShowError("lip.DownloadFile")
End Sub

Private Sub Unzip(PackageName As String, InstallPath As String)
On Error GoTo Errorhandler
    Dim FSO As Object
    Dim oApp As Object
    Dim Fname As Variant
    Dim FileNameFolder As Variant
    Dim DefPath As String
    Dim strDate As String

    Fname = InstallPath + PackageName + ".zip"
    FileNameFolder = InstallPath & PackageName & "\"

    On Error Resume Next
    Set FSO = CreateObject("scripting.filesystemobject")
    'Delete files
    FSO.DeleteFile FileNameFolder & "*.*", True
    'Delete subfolders
    FSO.DeleteFolder FileNameFolder & "*.*", True

    'Make the normal folder in DefPath
    MkDir FileNameFolder

    Set oApp = CreateObject("Shell.Application")
    oApp.Namespace(FileNameFolder).CopyHere oApp.Namespace(Fname).Items

    'Delete zip-file
    FSO.DeleteFile Fname, True

    Exit Sub
Errorhandler:
    Call UI.ShowError("lip.Unzip")
End Sub

Private Function InstallVBAComponents(PackageName As String, VBAModules As Object, InstallPath As String, Simulate As Boolean) As Boolean
On Error GoTo Errorhandler
    Dim bOk As Boolean
    bOk = True
    Dim VBAModule As Variant
    IncreaseIndent
    For Each VBAModule In VBAModules
        If addModule(PackageName, VBAModule.Item("name"), VBAModule.Item("relPath"), InstallPath, Simulate) = False Then
            bOk = False
        End If
    Next VBAModule
    DecreaseIndent
    InstallVBAComponents = bOk
    Exit Function
Errorhandler:
    InstallVBAComponents = False
    Call UI.ShowError("lip.InstallVBAComponents")
End Function

Private Function addModule(PackageName As String, ModuleName As String, RelPath As String, InstallPath As String, Simulate As Boolean) As Boolean
On Error GoTo Errorhandler
    Dim bOk As Boolean
    bOk = True
    If PackageName <> "" And ModuleName <> "" Then
        Dim VBComps As Object
        Dim Path As String
        Dim tempModuleName As String

        Set VBComps = Application.VBE.ActiveVBProject.VBComponents
        If ComponentExists(ModuleName, VBComps) = True Then
            If vbYes = Lime.MessageBox("Do you want to replace existing VBA-module """ & ModuleName & """?", vbYesNo + vbDefaultButton2 + vbQuestion) Then
                tempModuleName = LCO.GenerateGUID
                tempModuleName = VBA.Replace(VBA.Mid(tempModuleName, 2, VBA.Len(tempModuleName) - 2), "-", "")
                tempModuleName = VBA.Left("OLD_" & tempModuleName, 30)
                VBComps.Item(ModuleName).Name = tempModuleName
                
                If vbYes = Lime.MessageBox("Do you want to delete the old module?", vbYesNo + vbDefaultButton2 + vbQuestion) Then
                    If Not Simulate Then
                        Call VBComps.Remove(VBComps.Item(tempModuleName))
                    End If
                Else
                    Call Lime.MessageBox("Old module is saved with the name """ & tempModuleName & """", vbInformation)
                    sLog = sLog + ("Old module is saved with the name """ & tempModuleName & """") + vbNewLine
                End If
                
                Path = InstallPath + PackageName + "\" + Replace(RelPath, "/", "\")
                If Not Simulate Then
                    Call Application.VBE.ActiveVBProject.VBComponents.Import(Path)
                End If
                sLog = sLog + Indent + "Added " + ModuleName + vbNewLine
            Else
                sLog = sLog + ("Module """ & ModuleName & """ already exists and have not been replaced.") + vbNewLine
            End If
        Else
            Path = InstallPath + PackageName + "\" + Replace(RelPath, "/", "\")
            If Not Simulate Then
                Call Application.VBE.ActiveVBProject.VBComponents.Import(Path)
            End If
            sLog = sLog + Indent + "Added " + ModuleName + vbNewLine
        End If
    Else
        bOk = False
        sLog = sLog + (Indent + "Detected invalid package- or modulename while installing """ + RelPath + """") + vbNewLine
    End If
    addModule = bOk
    Exit Function
Errorhandler:
    addModule = False
    Call UI.ShowError("lip.addModule")
    sLog = sLog + ("Couldn't add module " & ModuleName) + vbNewLine
End Function

Private Function ComponentExists(ComponentName As String, VBComps As Object) As Boolean
On Error GoTo Errorhandler
    Dim VBComp As Variant

    For Each VBComp In VBComps
        If VBComp.Name = ComponentName Then
             ComponentExists = True
             Exit Function
        End If
    Next VBComp

    ComponentExists = False

    Exit Function
Errorhandler:
    Call UI.ShowError("lip.ComponentExists")
End Function

Private Function WriteToPackageFile(PackageName As String, Version As String, Simulate As Boolean) As Boolean
On Error GoTo Errorhandler
    Dim bOk As Boolean
    Dim oJSON As Object
    Dim fs As Object
    Dim a As Object
    Dim Line As Variant
    
    bOk = True
    Set oJSON = ReadPackageFile

    oJSON.Item("dependencies").Item(PackageName) = Version
    
    If Not Simulate Then
        Set fs = CreateObject("Scripting.FileSystemObject")
        Set a = fs.CreateTextFile(WebFolder + "packages.json", True)
        For Each Line In Split(PrettyPrintJSON(JSON.toString(oJSON)), vbCrLf)
            Line = VBA.Replace(Line, "\/", "/") 'Replace \/ with only / since JSON escapes frontslash with a backslash which causes problems with packagestores URLs
            a.WriteLine Line
        Next Line
        a.Close
    End If
    
    WriteToPackageFile = bOk
    Exit Function
Errorhandler:
    WriteToPackageFile = False
    Call UI.ShowError("lip.WriteToPackageFile")
End Function

Private Function PrettyPrintJSON(JSON As String) As String
On Error GoTo Errorhandler
    Dim i As Integer
    Dim Indent As String
    Dim PrettyJSON As String
    Dim InsideQuotation As Boolean

    For i = 1 To Len(JSON)
        Select Case Mid(JSON, i, 1)
            Case """"
                PrettyJSON = PrettyJSON + Mid(JSON, i, 1)
                If InsideQuotation = False Then
                    InsideQuotation = True
                Else
                    InsideQuotation = False
                End If
            Case "{", "["
                If InsideQuotation = False Then
                    Indent = Indent + "    " ' Add to indentation
                    PrettyJSON = PrettyJSON + "{" + vbCrLf + Indent
                Else
                    PrettyJSON = PrettyJSON + Mid(JSON, i, 1)
                End If
            Case "}", "["
                If InsideQuotation = False Then
                    Indent = Left(Indent, Len(Indent) - 4) 'Remove indentation
                    PrettyJSON = PrettyJSON + vbCrLf + Indent + "}"
                Else
                    PrettyJSON = PrettyJSON + Mid(JSON, i, 1)
                End If
            Case ","
                If InsideQuotation = False Then
                    PrettyJSON = PrettyJSON + "," + vbCrLf + Indent
                Else
                    PrettyJSON = PrettyJSON + Mid(JSON, i, 1)
                End If
            Case Else
                PrettyJSON = PrettyJSON + Mid(JSON, i, 1)
        End Select
    Next i
    PrettyPrintJSON = PrettyJSON

    Exit Function
Errorhandler:
    PrettyPrintJSON = ""
    Call UI.ShowError("lip.PrettyPrintJSON")
End Function

Private Function ReadPackageFile() As Object
On Error GoTo Errorhandler
    Dim sJSON As String
    Dim oJSON As Object
    sJSON = getJSON(WebFolder + "packages.json")

    If sJSON = "" Then
        sLog = sLog + Indent + "Error: No packages.json found!" + vbNewLine
        Set ReadPackageFile = Nothing
        Exit Function
    End If

    Set oJSON = JSON.parse(sJSON)
    Set ReadPackageFile = oJSON

    Exit Function
Errorhandler:
    Set ReadPackageFile = Nothing
    Call UI.ShowError("lip.ReadPackageFile")
End Function

Private Function FindPackageLocally(PackageName As String) As Object
On Error GoTo Errorhandler
    Dim InstalledPackages As Object
    Dim Package As Object
    Dim ReturnDict As New Scripting.Dictionary
    Dim oPackageFile As Object
    Set oPackageFile = ReadPackageFile

    If Not oPackageFile Is Nothing Then

        If oPackageFile.Exists("dependencies") Then
            Set InstalledPackages = oPackageFile.Item("dependencies")
            If InstalledPackages.Exists(PackageName) = True Then
                Call ReturnDict.Add(PackageName, InstalledPackages.Item(PackageName))
                Set FindPackageLocally = ReturnDict
                Exit Function
            End If
        Else
            sLog = sLog + Indent + ("Couldn't find dependencies in packages.json") + vbNewLine
        End If

    End If

    Set FindPackageLocally = Nothing
    Exit Function
Errorhandler:
    Set FindPackageLocally = Nothing
    Call UI.ShowError("lip.FindPackageLocally")
End Function

Private Sub CreateANewPackageFile()
On Error GoTo Errorhandler
    Dim fs As Object
    Dim a As Object
    Set fs = CreateObject("Scripting.FileSystemObject")
    Set a = fs.CreateTextFile(WebFolder + "packages.json", True)
    a.WriteLine ("{")
    a.WriteLine ("    ""stores"":{")
    a.WriteLine ("        ""PackageStore"":""http://api.lime-bootstrap.com/packages/"",")
    a.WriteLine ("        ""Bootstrap Appstore"":""http://api.lime-bootstrap.com/apps/""")
    a.WriteLine ("    },")
    a.WriteLine ("    ""dependencies"":{")
    a.WriteLine ("    }")
    a.WriteLine ("}")
    a.Close
    Exit Sub
Errorhandler:
    Call UI.ShowError("lip.CreateNewPackageFile")
End Sub

Public Function GetAllInstalledPackages() As String
On Error GoTo Errorhandler
    Dim oPackageFile As Object
    Set oPackageFile = ReadPackageFile()

    If Not oPackageFile Is Nothing Then
        GetAllInstalledPackages = JSON.toString(oPackageFile)
    Else
        GetAllInstalledPackages = "{}"
        sLog = sLog + Indent + ("Couldn't find dependencies in packages.json") + vbNewLine
    End If

    Exit Function
Errorhandler:
    Call UI.ShowError("lip.GetInstalledPackages")
End Function

Public Sub InstallLIP()
On Error GoTo Errorhandler
    Dim InstallPath As String
    
    sLog = ""

    sLog = sLog + Indent + "Creating a new packages.json file..." + vbNewLine
    Call CreateANewPackageFile
    Dim FSO As New FileSystemObject
    InstallPath = ThisApplication.WebFolder & DefaultInstallPath
    If Not FSO.FolderExists(InstallPath) Then
        FSO.CreateFolder InstallPath
    End If

    sLog = sLog + Indent + "Installing JSON-lib..." + vbNewLine
    Call DownloadFile("vba_json", BaseURL + ApiURL, InstallPath)
    Call Unzip("vba_json", InstallPath)
    Call addModule("vba_json", "JSON", "JSON.bas", InstallPath, False)
    Call addModule("vba_json", "cStringBuilder", "cStringBuilder.cls", InstallPath, False)

    Call WriteToPackageFile("vba_json", "1", False)

    sLog = sLog + Indent + "Install of LIP complete!" + vbNewLine
    Exit Sub
Errorhandler:
    Call UI.ShowError("lip.InstallLIP")
End Sub

Private Function AddOrCheckLocalize(sOwner As String, sCode As String, sDescription As String, sEN_US As String, sSV As String, sNO As String, sFI As String, Simulate As Boolean) As Boolean
On Error GoTo Errorhandler
    Dim oFilter As New LDE.Filter
    Dim oRecs As New LDE.Records

    Call oFilter.AddCondition("owner", lkOpEqual, sOwner)
    Call oFilter.AddCondition("code", lkOpEqual, sCode)
    Call oFilter.AddOperator(lkOpAnd)

    If oFilter.HitCount(Database.Classes("localize")) = 0 Then
        sLog = sLog + (Indent + "Localization " & sOwner & "." & sCode & " not found, creating new!") + vbNewLine
        If Not Simulate Then
            Dim oRec As New LDE.record
            Call oRec.Open(Database.Classes("localize"))
            oRec.Value("owner") = sOwner
            oRec.Value("code") = sCode
            oRec.Value("context") = sDescription
            oRec.Value("sv") = sSV
            oRec.Value("en_us") = sEN_US
            oRec.Value("no") = sNO
            oRec.Value("fi") = sFI
            Call oRec.Update
        End If
    ElseIf oFilter.HitCount(Database.Classes("localize")) = 1 Then
        sLog = sLog + (Indent + "Updating localization " & sOwner & "." & sCode) + vbNewLine
        
        If Not Simulate Then
            Call oRecs.Open(Database.Classes("localize"), oFilter)
            oRecs(1).Value("owner") = sOwner
            oRecs(1).Value("code") = sCode
            oRecs(1).Value("context") = sDescription
            oRecs(1).Value("sv") = sSV
            oRecs(1).Value("en_us") = sEN_US
            oRecs(1).Value("no") = sNO
            oRecs(1).Value("fi") = sFI
            Call oRecs.Update
        End If

    Else
        sLog = sLog + "There are multiple copies of " & sOwner & "." & sCode & ". Fix this and try again."
    End If

    Set Localize.dicLookup = Nothing
    AddOrCheckLocalize = True
    Exit Function
Errorhandler:
    sLog = sLog + Indent + ("Error while validating or adding Localize") + vbNewLine
    AddOrCheckLocalize = False
End Function

Private Sub IncreaseIndent()
On Error GoTo Errorhandler
    Indent = Indent + IndentLenght
    Exit Sub
Errorhandler:
    Call UI.ShowError("lip.IncreaseIndent")
End Sub

Private Sub DecreaseIndent()
On Error GoTo Errorhandler

    If Len(Indent) - Len(IndentLenght) > 0 Then
        Indent = Left(Indent, Len(Indent) - Len(IndentLenght))
    Else
        Indent = ""
    End If
    
    Exit Sub
Errorhandler:
    Call UI.ShowError("lip.DecreaseIndent")
End Sub

Private Function InstallRelations(oJSON As Object, Simulate As Boolean) As Boolean
On Error GoTo Errorhandler
    Dim bOk As Boolean
    Dim relation As Object
    Dim oProc As LDE.Procedure

    Dim errormessage As String
    bOk = True

    sLog = sLog + Indent + "Adding relations..." + vbNewLine
    IncreaseIndent

    For Each relation In oJSON
    
        errormessage = ""

        Set oProc = Database.Procedures("csp_lip_addRelations")

        If Not oProc Is Nothing Then

            sLog = sLog + Indent + "Add relation between: " + relation.Item("table1") + "." + relation.Item("field1") + " and " + relation.Item("table2") + "." + relation.Item("field2") + vbNewLine

            oProc.Parameters("@@table1").InputValue = relation.Item("table1")
            oProc.Parameters("@@field1").InputValue = relation.Item("field1")
            oProc.Parameters("@@table2").InputValue = relation.Item("table2")
            oProc.Parameters("@@field2").InputValue = relation.Item("field2")
            oProc.Parameters("@@simulate").InputValue = Simulate

            Call oProc.Execute(False)

            errormessage = oProc.Parameters("@@errorMessage").OutputValue

            'If errormessage is set, something went wrong
            If errormessage <> "" Then
                sLog = sLog + Indent + (errormessage) + vbNewLine
                bOk = False
            Else
                sLog = sLog + Indent + ("Relation between: " + relation.Item("table1") + "." + relation.Item("field1") + " and " + relation.Item("table2") + "." + relation.Item("field2") + " created.") + vbNewLine
            End If
            
            DecreaseIndent

        Else
            bOk = False
            Call Lime.MessageBox("Couldn't find SQL-procedure 'csp_lip_addRelations'. Please make sure this procedure exists in the database and restart LDC.")
        End If

    Next relation
    DecreaseIndent

    Set oProc = Nothing
    
    InstallRelations = bOk

    Exit Function
Errorhandler:
    Set oProc = Nothing
    InstallRelations = False
    Call UI.ShowError("lip.InstallRelations")
End Function

