unit xeSetup;

interface

uses
  Classes,
  // xedit units
  wbHelpers, wbInterface, wbImplementation;

type
  {$region 'Types'}
  TLoaderThread = class(TThread)
  protected
    procedure Execute; override;
  end;
  TRefThread = class(TThread)
  protected
    procedure Execute; override;
  end;
  {$endregion}

  {$region 'Native functions}
  procedure UpdateFileCount;
  procedure LoadPluginFiles;
  procedure LoadResources;
  procedure BuildPluginsList(const sLoadPath: String; var sl: TStringList);
  procedure BuildLoadOrder(const sLoadPath: String; var slLoadOrder, slPlugins: TStringList);
  procedure RemoveCommentsAndEmpty(var sl: TStringList);
  procedure RemoveMissingFiles(var sl: TStringList);
  procedure AddMissingFiles(var sl: TStringList);
  procedure GetPluginDates(var sl: TStringList);
  procedure AddBaseMasters(var sl: TStringList);
  procedure FixLoadOrder(var sl: TStringList; const filename: String; index: Integer);
  function PluginListCompare(List: TStringList; Index1, Index2: Integer): Integer;
  procedure RenameSavedFiles;
  {$endregion}

  {$region 'API functions'}
  function SetGamePath(path: PWideChar): WordBool; cdecl;
  function SetLanguage(lang: PWideChar): WordBool; cdecl;
  function SetBackupPath(path: PWideChar): WordBool; cdecl;
  function SetGameMode(mode: Integer): WordBool; cdecl;
  function GetGamePath(mode: Integer; len: PInteger): WordBool; cdecl;
  function GetLoadOrder(len: PInteger): WordBool; cdecl;
  function GetActivePlugins(len: PInteger): WordBool; cdecl;
  function LoadPlugins(loadOrder: PWideChar): WordBool; cdecl;
  function LoadPlugin(filename: PWideChar): WordBool; cdecl;
  function BuildReferences(_id: Cardinal): WordBool; cdecl;
  function GetLoaderDone: WordBool; cdecl;
  function UnloadPlugin(_id: Cardinal): WordBool; cdecl;
  {$endregion}

var
  xFiles, rFiles: array of IwbFile;
  slLoadOrder, slSavedFiles: TStringList;
  LoaderThread: TLoaderThread;
  RefThread: TRefThread;
  BaseFileIndex: Integer;

implementation

uses
  Windows, SysUtils, ShlObj,
  // mte units
  mteHelpers,
  // xelib units
  xeMeta, xeConfiguration, xeMessages, xeMasters;

{$region 'TLoaderThread'}
procedure TLoaderThread.Execute;
begin
  try
    LoadPluginFiles;
    LoadResources;
    UpdateFileCount;

    // done loading
    ProgramStatus.bLoaderDone := True;
    AddMessage('Done loading files.');
  except
    on E: Exception do begin
      AddMessage('Fatal Error: <' + e.ClassName + ': ' + e.Message + '>');
      wbLoaderError := True;
    end;
  end;
end;
{$endregion}

{$region 'TRefThread'}
procedure TRefThread.Execute;
var
  i: Integer;
  _file: IwbFile;
begin
  try
    for i := Low(rFiles) to High(rFiles) do begin
      _file := rFiles[i];
      AddMessage(Format('Building references for %s (%d/%d)', [_file.FileName, i + 1, Length(rFiles)]));
      rFiles[i].BuildRef;
    end;

    // done loading
    SetLength(rFiles, 0);
    ProgramStatus.bLoaderDone := True;
    AddMessage('Done building references.');
  except
    on E: Exception do begin
      AddMessage('Fatal Error: <' + e.ClassName + ': ' + e.Message + '>');
      wbLoaderError := True;
    end;
  end;
end;
{$endregion}

{$region 'Native functions'}
{$region 'File loading'}
procedure UpdateFileCount;
begin
  Globals.Values['FileCount'] := IntToStr(Length(xFiles));
end;

procedure LoadFile(const filePath: String; loadOrder: Integer);
var
  _file: IwbFile;
begin
  _file := wbFile(filePath, loadOrder, '', False, False);
  _file._AddRef;
  SetLength(xFiles, Length(xFiles) + 1);
  xFiles[High(xFiles)] := _file;
end;

procedure LoadHardcodedDat;
var
  _file: IwbFile;
begin
  _file := wbFile(Globals.Values['ProgramPath'] + wbGameName + wbHardcodedDat, 0);
  _file._AddRef;
  SetLength(xFiles, Length(xFiles) + 1);
  xFiles[High(xFiles)] := _file;
end;

procedure LoadPluginFiles;
var
  i: Integer;
  sFileName: String;
begin
  BaseFileIndex := Length(xFiles);
  for i := 0 to Pred(slLoadOrder.Count) do begin
    sFileName := slLoadOrder[i];
    AddMessage(Format('Loading %s (%d/%d)', [sFileName, i + 1, slLoadOrder.Count]));

    // load plugin
    try
      LoadFile(wbDataPath + sFileName, BaseFileIndex + i);
    except
      on x: Exception do begin
        AddMessage('Exception loading ' + sFileName);
        AddMessage(x.Message);
        raise x;
      end;
    end;

    // load hardcoded dat
    if (i = 0) and (sFileName = wbGameName + '.esm') then try
      LoadHardCodedDat;
    except
      on x: Exception do begin
        AddMessage('Exception loading ' + wbGameName + wbHardcodedDat);
        raise x;
      end;
    end;
  end;
end;

procedure LoadBSAFile(const sFileName: String);
var
  sFileExt: String;
begin
  sFileExt := ExtractFileExt(sFileName);
  AddMessage('Loading resources from ' + sFileName);
  if sFileExt = '.bsa' then
    wbContainerHandler.AddBSA(wbDataPath + sFileName)
  else if sFileExt = '.ba2' then
    wbContainerHandler.AddBA2(wbDataPath + sFileName);
end;

procedure LoadBSAs(var slBSAFileNames, slErrors: TStringList);
var
  i: Integer;
begin
  for i := 0 to slBSAFileNames.Count - 1 do
    LoadBSAFile(slBSAFileNames[i]);
  for i := 0 to slErrors.Count - 1 do
    AddMessage(slErrors[i] + ' was not found');
end;

procedure LoadResources;
var
  slBSAFileNames: TStringList;
  slErrors: TStringList;
  i: Integer;
  modName: String;
  bIsTES5: Boolean;
begin
  wbContainerHandler.AddFolder(wbDataPath);
  bIsTES5 := wbGameMode in [gmTES5, gmSSE];
  slBSAFileNames := TStringList.Create;
  try
    slErrors := TStringList.Create;
    try
      if BaseFileIndex = 0 then begin
        FindBSAs(wbTheGameIniFileName, wbDataPath, slBSAFileNames, slErrors);
        LoadBSAs(slBSAFileNames, slErrors);
      end;

      for i := BaseFileIndex to High(xFiles) do begin
        slBSAFileNames.Clear;
        slErrors.Clear;
        modName := ChangeFileExt(xFiles[i].GetFileName, '');
        HasBSAs(modName, wbDataPath, bIsTES5, bIsTES5, slBSAFileNames, slErrors);
        LoadBSAs(slBSAFileNames, slErrors);
      end;
    finally
      slErrors.Free;
    end;
  finally
    slBSAFileNames.Free;
  end;
end;

function IndexOfFile(const _file: IwbFile): Integer;
begin
  for Result := Low(xFiles) to High(xFiles) do
    if xFiles[Result] = _file then exit;
  Result := -1;
end;

procedure ForceClose(const _file: IwbFile);
var
  i, index, len: Integer;
begin
  index := IndexOfFile(_file);
  len := Length(xFiles);
  Assert(index > -1);
  Assert(index < len);
  for i := index + 1 to Pred(len) do
    xFiles[i - 1] := xFiles[i];
  SetLength(xFiles, len - 1);
  wbFileForceClosed(_file);
  UpdateFileCount;
end;
{$endregion}

{$region 'Load order helpers'}
procedure BuildPluginsList(const sLoadPath: String; var sl: TStringList);
var
  sPath: String;
begin
  sPath := sLoadPath + 'plugins.txt';
  if FileExists(sPath) then
    sl.LoadFromFile(sPath)
  else
    AddMissingFiles(sl);

  // remove comments and missing files
  RemoveCommentsAndEmpty(sl);
  RemoveMissingFiles(sl);
end;

procedure BuildLoadOrder(const sLoadPath: String; var slLoadOrder, slPlugins: TStringList);
var
  sPath: String;
begin
  sPath := sLoadPath + 'loadorder.txt';
  if FileExists(sPath) then
    slLoadOrder.LoadFromFile(sPath)
  else
    slLoadOrder.AddStrings(slPlugins);

  // remove comments and add/remove files
  RemoveCommentsAndEmpty(slLoadOrder);
  RemoveMissingFiles(slLoadOrder);
  AddMissingFiles(slLoadOrder);
end;

{ Remove comments and empty lines from a stringlist }
procedure RemoveCommentsAndEmpty(var sl: TStringList);
var
  i, j, k: integer;
  s: string;
begin
  for i := Pred(sl.Count) downto 0 do begin
    s := Trim(sl.Strings[i]);
    j := Pos('#', s);
    k := Pos('*', s);
    if j > 0 then
      System.Delete(s, j, High(Integer));
    if s = '' then
      sl.Delete(i);
    if k = 1 then
      sl[i] := Copy(s, 2, Length(s));
  end;
end;

{ Remove nonexistent files from stringlist }
procedure RemoveMissingFiles(var sl: TStringList);
var
  i: integer;
begin
  for i := Pred(sl.Count) downto 0 do
    if not FileExists(wbDataPath + sl.Strings[i]) then
      sl.Delete(i);
end;

{ Add missing *.esp and *.esm files to list }
procedure AddMissingFiles(var sl: TStringList);
var
  F: TSearchRec;
  i, j: integer;
  slNew: TStringList;
begin
  slNew := TStringList.Create;
  try
    // search for missing plugins and masters
    if FindFirst(wbDataPath + '*.*', faAnyFile, F) = 0 then try
      repeat
        if not (IsFileESM(F.Name) or IsFileESP(F.Name)) then
          continue;
        if sl.IndexOf(F.Name) = -1 then
          slNew.AddObject(F.Name, TObject(FileAge(wbDataPath + F.Name)));
      until FindNext(F) <> 0;
    finally
      FindClose(F);
    end;

    // sort the list
    slNew.CustomSort(PluginListCompare);

    // The for loop won't initialize j if sl.count = 0, we must force it
    // to -1 so inserting will happen at index 0
    if sl.Count = 0 then
      j := -1
    else
      // find position of last master
      for j := Pred(sl.Count) downto 0 do
        if IsFileESM(sl[j]) then
          Break;

    // add esm masters after the last master, add esp plugins at the end
    Inc(j);
    for i := 0 to Pred(slNew.Count) do begin
      if IsFileESM(slNew[i]) then begin
        sl.InsertObject(j, slNew[i], slNew.Objects[i]);
        Inc(j);
      end else
        sl.AddObject(slNew[i], slNew.Objects[i]);
    end;
  finally
    slNew.Free;
  end;
end;

{ Get date modified for plugins in load order and store in stringlist objects }
procedure GetPluginDates(var sl: TStringList);
var
  i: Integer;
begin
  for i := 0 to Pred(sl.Count) do
    sl.Objects[i] := TObject(FileAge(wbDataPath + sl[i]));
end;

procedure AddBaseMasters(var sl: TStringList);
begin
  if (wbGameMode = gmTES5) then begin
    FixLoadOrder(sl, 'Skyrim.esm', 0);
    FixLoadOrder(sl, 'Update.esm', 1);
  end
  else if (wbGameMode = gmSSE) then begin
    FixLoadOrder(sl, 'Skyrim.esm', 0);
    FixLoadOrder(sl, 'Update.esm', 1);
    FixLoadOrder(sl, 'Dawnguard.esm', 2);
    FixLoadOrder(sl, 'Hearthfires.esm', 3);
    FixLoadOrder(sl, 'Dragonborn.esm', 4);
  end
  else if (wbGameMode = gmFO4) then begin
    FixLoadOrder(sl, 'Fallout4.esm', 0);
    FixLoadOrder(sl, 'DLCRobot.esm', 1);
    FixLoadOrder(sl, 'DLCworkshop01.esm', 2);
    FixLoadOrder(sl, 'DLCCoast.esm', 3);
    FixLoadOrder(sl, 'DLCworkshop02.esm', 4);
    FixLoadOrder(sl, 'DLCworkshop03.esm', 5);
    FixLoadOrder(sl, 'DLCNukaworld.esm', 6);
  end;
end;

{ Forces a plugin to load at a specific position }
procedure FixLoadOrder(var sl: TStringList; const filename: String; index: Integer);
var
  oldIndex: Integer;
begin
  oldIndex := sl.IndexOf(filename);
  if (oldIndex > -1) and (oldIndex <> index) then begin
    sl.Delete(oldIndex);
    sl.Insert(index, filename);
  end;
end;

{ Compare function for sorting load order by date modified/esms }
function PluginListCompare(List: TStringList; Index1, Index2: Integer): Integer;
var
  IsESM1, IsESM2: Boolean;
  FileAge1,FileAge2: Integer;
  FileDateTime1, FileDateTime2: TDateTime;
begin
  IsESM1 := IsFileESM(List[Index1]);
  IsESM2 := IsFileESM(List[Index2]);

  if IsESM1 = IsESM2 then begin
    FileAge1 := Integer(List.Objects[Index1]);
    FileAge2 := Integer(List.Objects[Index2]);

    if FileAge1 < FileAge2 then
      Result := -1
    else if FileAge1 > FileAge2 then
      Result := 1
    else begin
      if not SameText(List[Index1], List[Index1])
      and FileAge(List[Index1], FileDateTime1) and FileAge(List[Index2], FileDateTime2) then begin
        if FileDateTime1 < FileDateTime2 then
          Result := -1
        else if FileDateTime1 > FileDateTime2 then
          Result := 1
        else
          Result := 0;
      end else
        Result := 0;
    end;

  end else if IsESM1 then
    Result := -1
  else
    Result := 1;
end;
{$endregion}

{$region 'Rename saved files'}
var
  FileTimeStr: String;

procedure BackupFile(const path: String);
var
  bakPath: String;
begin
  if DirectoryExists(BackupPath) then
    bakPath := BackupPath + ExtractFileName(path) + '.' + FileTimeStr + '.bak'
  else
    bakPath := path + '.bak';
  if not RenameFile(path, bakPath) then
    RaiseLastOSError;
end;

procedure RenameSavedFile(const path: String);
var
  newPath: String;
begin
  newPath := Copy(path, 1, Length(path) - 5);
  if FileExists(newPath) then
    BackupFile(newPath);
  if not RenameFile(path, newPath) then
    RaiseLastOSError;
end;

procedure CreateBackupFolder;
begin
  try
    ForceDirectories(BackupPath);
  except
    on x: Exception do
      AddMessage('Error creating backup folder: ' + x.Message);
  end;
end;

procedure RenameSavedFiles;
var
  i: Integer;
begin
  CreateBackupFolder;
  DateTimeToString(FileTimeStr, 'yymmdd_hhnnss', Now);
  for i := 0 to Pred(slSavedFiles.Count) do try
    RenameSavedFile(slSavedFiles[i]);
  except
    on x: Exception do
      AddMessage('Error renaming saved file, ' + x.Message);
  end;
end;
{$endregion}
{$endregion}

{$region 'API functions'}
function SetGamePath(path: PWideChar): WordBool; cdecl;
begin
  Result := False;
  try
    GamePath := string(path);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function SetLanguage(lang: PWideChar): WordBool; cdecl;
begin
  Result := False;
  try
    Language := string(lang);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function SetBackupPath(path: PWideChar): WordBool; cdecl;
begin
  Result := False;
  try
    BackupPath := string(path);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function SetGameMode(mode: Integer): WordBool; cdecl;
begin
  Result := False;
  try
    if wbGameName <> '' then
      raise Exception.Create('Game mode already set to: ' + wbGameName);
    SetGame(mode);
    // log message
    AddMessage(Format('Game: %s, DataPath: %s', [wbGameName, wbDataPath]));
    // set global values
    Globals.Values['GameName'] := ProgramStatus.GameMode.gameName;
    Globals.Values['AppName'] := ProgramStatus.GameMode.appName;
    Globals.Values['LongGameName'] := ProgramStatus.GameMode.longName;
    Globals.Values['DataPath'] := wbDataPath;
    Globals.Values['AppDataPath'] := wbAppDataPath;
    Globals.Values['MyGamesPath'] := wbMyGamesPath;
    Globals.Values['GameIniPath'] := wbTheGameIniFileName;
    // success
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function GetGamePath(mode: Integer; len: PInteger): WordBool; cdecl;
begin
  Result := False;
  try
    resultStr := NativeGetGamePath(GameArray[mode]);
    if resultStr <> '' then begin
      len^ := Length(resultStr);
      Result := True;
    end;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function GetLoadOrder(len: PInteger): WordBool; cdecl;
var
  slPlugins, slLoadOrder: TStringList;
  sLoadPath: String;
begin
  Result := False;
  try
    slPlugins := TStringList.Create;
    slLoadOrder := TStringList.Create;

    try
      sLoadPath := Globals.Values['AppDataPath'];
      BuildPluginsList(sLoadPath, slPlugins);
      BuildLoadOrder(sLoadPath, slLoadOrder, slPlugins);

      // add base masters if missing
      AddBaseMasters(slPlugins);
      AddBaseMasters(slLoadOrder);

      // if GameMode is not Skyrim, SkyrimSE or Fallout 4 sort
      // by date modified
      if not (wbGameMode in [gmTES5, gmSSE, gmFO4]) then begin
        GetPluginDates(slLoadOrder);
        slLoadOrder.CustomSort(PluginListCompare);
      end;

      // SET RESULT STRING
      resultStr := slLoadOrder.Text;
      Delete(resultStr, Length(resultStr) - 1, 2);
      len^ := Length(resultStr);
      Result := True;
    finally
      slPlugins.Free;
      slLoadOrder.Free;
    end;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function GetActivePlugins(len: PInteger): WordBool; cdecl;
var
  slPlugins: TStringList;
  sLoadPath: String;
begin
  Result := False;
  try
    slPlugins := TStringList.Create;

    try
      sLoadPath := Globals.Values['AppDataPath'];
      BuildPluginsList(sLoadPath, slPlugins);
      AddBaseMasters(slPlugins);

      // SET RESULT STRING
      resultStr := slPlugins.Text;
      Delete(resultStr, Length(resultStr) - 1, 2);
      len^ := Length(resultStr);
      Result := True;
    finally
      slPlugins.Free;
    end;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function LoadPlugins(loadOrder: PWideChar): WordBool; cdecl;
begin
  Result := False;
  try
    // exit if we have already started loading plugins
    if Assigned(slLoadOrder) then
      raise Exception.Create('Already loading plugins.');
    
    // store load order we're going to use in slLoadOrder
    ProgramStatus.bLoaderDone := False;
    slLoadOrder := TStringList.Create;
    slLoadOrder.Text := loadOrder;

    // start loader thread
    LoaderThread := TLoaderThread.Create;
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function LoadPlugin(filename: PWideChar): WordBool; cdecl;
begin
  Result := False;
  try
    // update load order
    ProgramStatus.bLoaderDone := False;
    slLoadOrder := TStringList.Create;
    slLoadOrder.Add(fileName);

    // start loader thread
    LoaderThread := TLoaderThread.Create;
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function BuildReferences(_id: Cardinal): WordBool; cdecl;
var
  _file: IwbFile;
begin
  Result := False;
  try
    ProgramStatus.bLoaderDone := False;
    if _id = 0 then
      rFiles := Copy(xFiles, 0, MaxInt)
    else begin
      if not Supports(Resolve(_id), IwbFile, _file) then
        raise Exception.Create('Interface must be a file.');
      SetLength(rFiles, 1);
      rFiles[0] := _file;
    end;
    RefThread := TRefThread.Create;
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function GetLoaderDone: WordBool; cdecl;
begin
  Result := ProgramStatus.bLoaderDone;
  if Result then begin
    if Assigned(LoaderThread) then FreeAndNil(LoaderThread);
    if Assigned(RefThread)    then FreeAndNil(RefThread);
    if Assigned(slLoadOrder)  then FreeAndNil(slLoadOrder);
  end;
end;

function UnloadPlugin(_id: Cardinal): WordBool; cdecl;
var
  _file: IwbFile;
  container: IwbContainer;
  i: Integer;
begin
  Result := False;
  try
    if not Supports(Resolve(_id), IwbFile, _file)
    or not Supports(_file, IwbContainer, container) then
      raise Exception.Create('Interface must be a file.');
    if csRefsBuild in container.GetContainerStates then
      raise Exception.Create('Cannot unload plugin which has had refs built.');
    for i := Low(xFiles) to High(xFiles) do
      if NativeFileHasMaster(xFiles[i], _file) then
        raise Exception.Create(Format('Cannot unload plugin %s, it is required by %s.', [_file.FileName, xFiles[i].FileName]));
    ForceClose(_file);
    Result := Release(_id);
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;
{$endregion}

initialization
  slSavedFiles := TStringList.Create;
finalization
  slSavedFiles.Free;

end.
