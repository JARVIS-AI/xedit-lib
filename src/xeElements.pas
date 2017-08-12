unit xeElements;

interface

uses
  Classes,
  //xedit units
  wbInterface,
  // xelib units
  xeMeta;

type
  TSmashType = ( stUnknown, stRecord, stString, stInteger, stFlag, stFloat,
    stStruct, stUnsortedArray, stUnsortedStructArray, stSortedArray,
    stSortedStructArray, stByteArray, stUnion );
  TSmashTypes = set of TSmashType;

  {$region 'Native functions'}
  function ResolveRecord(group: IwbGroupRecord; key, nextPath: String): IInterface;
  function ResolveGroupOrRecord(group: IwbGroupRecord; key, nextPath: String): IInterface; overload;
  function ResolveFromGroup(group: IwbGroupRecord; path: String): IInterface;
  function ResolveElement(e: IInterface; path: String): IInterface;
  function NativeGetElement(_id: Cardinal; key: PWideChar): IInterface;
  function NativeGetElementEx(_id: Cardinal; key: PWideChar): IwbElement;
  procedure NativeMoveArrayItem(element: IwbElement; index: Integer);
  function NativeContainer(element: IwbElement): IwbContainer;
  function AddGroupIfMissing(_file: IwbFile; sig: String): IwbGroupRecord;
  function CreateFromContainer(container: IwbContainerElementRef; path: String): IInterface;
  function CreateFromRecord(rec: IwbMainRecord; path: String): IInterface;
  function CreateRecord(group: IwbGroupRecord; formID: Cardinal; nextPath: String): IInterface; overload;
  function CreateGroupOrRecord(group: IwbGroupRecord; key, nextPath: String): IInterface; overload;
  function CreateFromGroup(group: IwbGroupRecord; path: String): IInterface;
  function CreateFile(fileName, nextPath: String): IInterface;
  function CreateElement(e: IInterface; path: String): IInterface;
  function NativeAddElement(_id: Cardinal; key: string): IInterface;
  function CopyElementToFile(const aSource: IwbElement; aFile: IwbFile; aAsNew, aDeepCopy: Boolean): IwbElement;
  function CopyElementToRecord(const aSource: IwbElement; aMainRecord: IwbMainRecord; aAsNew, aDeepCopy: Boolean): IwbElement;
  function IsChildGroup(group: IwbGroupRecord): Boolean;
  function IsSorted(e: IwbElement): Boolean;
  function IsArray(element: IwbElement): Boolean;
  function IsFormID(element: IwbElement): Boolean;
  function GetFlagsDef(element: IwbElement; var flagsDef: IwbFlagsDef): Boolean;
  function GetDefType(element: IwbElement): TwbDefType;
  function GetSmashType(element: IwbElement): TSmashType;
  {$endregion}

  {$region 'API functions'}
  function HasElement(_id: Cardinal; key: PWideChar; bool: PWordBool): WordBool; cdecl;
  function GetElement(_id: Cardinal; key: PWideChar; _res: PCardinal): WordBool; cdecl;
  function AddElement(_id: Cardinal; key: PWideChar; _res: PCardinal): WordBool; cdecl;
  function RemoveElement(_id: Cardinal; key: PWideChar): WordBool; cdecl;
  function RemoveElementOrParent(_id: Cardinal): WordBool; cdecl;
  function GetElements(_id: Cardinal; key: PWideChar; sortBy: Byte; len: PInteger): WordBool; cdecl;
  function GetLinksTo(_id: Cardinal; key: PWideChar; _res: PCardinal): WordBool; cdecl;
  function GetElementIndex(_id: Cardinal; index: PInteger): WordBool; cdecl;
  function GetContainer(_id: Cardinal; _res: PCardinal): WordBool; cdecl;
  function GetElementFile(_id: Cardinal; _res: PCardinal): WordBool; cdecl;
  function GetElementRecord(_id: Cardinal; _res: PCardinal): WordBool; cdecl;
  function ElementCount(_id: Cardinal; count: PInteger): WordBool; cdecl;
  function ElementEquals(_id, _id2: Cardinal; bool: PWordBool): WordBool; cdecl;
  function ElementMatches(_id: Cardinal; path, value: PWideChar; bool: PWordBool): WordBool; cdecl;
  function HasArrayItem(_id: Cardinal; path, subpath, value: PWideChar; bool: PWordBool): WordBool; cdecl;
  function GetArrayItem(_id: Cardinal; path, subpath, value: PWideChar; _res: PCardinal): WordBool; cdecl;
  function AddArrayItem(_id: Cardinal; path, subpath, value: PWideChar; _res: PCardinal): WordBool; cdecl;
  function RemoveArrayItem(_id: Cardinal; path, subpath, value: PWideChar): WordBool; cdecl;
  function MoveArrayItem(_id: Cardinal; index: Integer): WordBool; cdecl;
  function CopyElement(_id, _id2: Cardinal; aAsNew: WordBool; _res: PCardinal): WordBool; cdecl;
  function GetSignatureAllowed(_id: Cardinal; sig: PWideChar; bool: PWordBool): WordBool; cdecl;
  function SortKey(_id: Cardinal; len: PInteger): WordBool; cdecl;
  function ElementType(_id: Cardinal; enum: PByte): WordBool; cdecl;
  function DefType(_id: Cardinal; enum: PByte): WordBool; cdecl;
  function SmashType(_id: Cardinal; enum: PByte): WordBool; cdecl;
  {$endregion}

implementation

uses
  Variants, SysUtils,
  // mte units
  mteHelpers,
  // xedit units
  wbImplementation,
  // xelib units
  xeConfiguration, xeMessages, xeFiles, xeMasters, xeRecords, xeElementValues,
  xeSetup;

{$region 'Native functions'}
{$region 'Path parsing'}
function ParseIndex(key: string; var index: Integer): Boolean;
begin
  Result := (key[1] = '[') and (key[Length(key)] = ']');
  if Result then
    index := StrToInt(Copy(key, 2, Length(key) - 2));
end;

function CheckIndex(maxIndex: Integer; var index: Integer): Boolean;
begin
  if index = -1 then
    index := maxIndex;
  Result := (index > -1) and (index <= maxIndex);
end;

function IsHexStr(key: String): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to Length(key) do
    if not CharInSet(key[i], ['A'..'F','0'..'9']) then exit;
  Result := True;
end;

function ParseFormID(key: String; var formID: Cardinal): Boolean;
begin
  Result := (Length(key) = 8) and IsHexStr(key);
  if Result then
    formID := StrToInt('$' + key);
end;

function ParseFullName(value: String; var fullName: String): Boolean;
begin
  Result := (value[1] = '"') and (value[Length(value)] = '"');
  if Result then
    fullName := Copy(value, 2, Length(value) - 2);
end;

function GetSignatureFromName(name: String; var signature: TwbSignature): Boolean;
var
  index: Integer;
begin
  index := slSignatureNameMap.IndexOf(name);
  Result := index > -1;
  if Result then
    signature := TwbSignature(slSignatureNameMap.Names[index])
end;

procedure SplitPath(path: String; var key, nextPath: String);
var
  i: Integer;
begin
  i := Pos('\', path);
  if i > 0 then begin
    key := Copy(path, 1, i - 1);
    nextPath := Copy(path, i + 1, Length(path));
  end
  else
    key := path;
end;
{$endregion}

{$region 'Element resolution'}
function ResolveByIndex(container: IwbContainerElementRef; index: Integer; nextPath: String): IInterface;
begin
  Result := nil;

  // resolve element from container if container present
  // else resolve file at index
  if Assigned(container) then begin
    if CheckIndex(container.ElementCount - 1, index) then
      Result := container.Elements[index];
  end
  else begin
    if CheckIndex(High(xFiles), index) then
      Result := NativeFileByIndex(index);
  end;

  // resolve next element if nextPath is present
  if Assigned(Result) and (nextPath <> '') then
    Result := ResolveElement(Result, nextPath);
end;

function ResolveFromContainer(container: IwbContainerElementRef; path: String): IInterface;
begin
  Result := container.ElementByPath[path];
end;

function ResolveChildGroup(rec: IwbMainRecord; nextPath: String): IInterface;
begin
  Result := rec.ChildGroup;
  if Assigned(Result) and (nextPath <> '') then
    Result := ResolveFromGroup(Result as IwbGroupRecord, nextPath);
end;

function ResolveFromRecord(rec: IwbMainRecord; path: String): IInterface;
var
  key, nextPath: String;
  container: IwbContainerElementRef;
begin
  Result := nil;
  SplitPath(path, key, nextPath);
  if SameText(key, 'Child Group') then
    Result := ResolveChildGroup(rec, nextPath)
  else if Supports(rec, IwbContainerElementRef, container) then
    Result := ResolveFromContainer(container, path);
end;

function FindRecordOrGroup(group: IwbGroupRecord; searchKey: String): IInterface;
var
  i: Integer;
  element: IwbElement;
  rec: IwbMainRecord;
  grp: IwbGroupRecord;
begin
  for i := 0 to Pred(group.ElementCount) do begin
    element := group.Elements[i];
    if Supports(element, IwbMainRecord, rec) then begin
      if SameText(rec.EditorID, searchKey) then begin
        Result := rec;
        exit;
      end;
    end
    else if Supports(element, IwbGroupRecord, grp) then begin
      if SameText(grp.ShortName, searchKey) then begin
        Result := grp;
        exit;
      end;
    end;
  end;
end;

function ResolveRecord(group: IwbGroupRecord; key, nextPath: String): IInterface;
var
  name: String;
  formID: Cardinal;
begin
  if ParseFormID(key, formID) then
    Result := group._File.RecordByFormID[formID, True]
  else if ParseFullName(key, name) then
    Result := group.MainRecordByName[name]
  else
    Result := group.MainRecordByEditorID[key];
  if Assigned(Result) and (nextPath <> '') then
    Result := ResolveFromRecord(Result as IwbMainRecord, nextPath);
end;

function ResolveGroupOrRecord(group: IwbGroupRecord; key, nextPath: String): IInterface; overload;
var
  name, sig: String;
  formID: Cardinal;
  grp: IwbGroupRecord;
  rec: IwbMainRecord;
begin
  Result := nil;
  if ParseFormID(key, formID) then
    Result := group._File.RecordByFormID[formID, True]
  else if ParseFullName(key, name) then
    Result := group.MainRecordByName[name]
  else begin
    sig := String(TwbSignature(group.GroupLabel));
    if group._File.EditorIDSorted(sig) then
      Result := group._File.RecordByEditorID[key];
    if not Assigned(Result) then
      Result := FindRecordOrGroup(group, key);
  end;
  if nextPath <> '' then begin
    if Supports(Result, IwbGroupRecord, grp) then
      Result := ResolveFromGroup(grp, nextPath)
    else if Supports(Result, IwbMainRecord, rec) then
      Result := ResolveFromRecord(rec, nextPath);
  end;
end;

function ResolveFromGroup(group: IwbGroupRecord; path: String): IInterface;
var
  key, nextPath: String;
  index: Integer;
begin
  SplitPath(path, key, nextPath);
  // resolve element by index if key is an index
  // else resolve main record by FormID/EditorID/Name
  if ParseIndex(key, index) then
    Result := ResolveByIndex(group as IwbContainerElementRef, index, nextPath)
  else
    Result := ResolveGroupOrRecord(group, key, nextPath);
end;

function ResolveGroupOrRecord(_file: IwbFile; key: String; nextPath: String): IInterface; overload;
var
  formID: Cardinal;
  name: String;
  sig: TwbSignature;
  rec: IwbMainRecord;
  group: IwbGroupRecord;
begin
  if ParseFormID(key, formID) then
    Result := _file.RecordByFormID[formID, True]
  else if ParseFullName(key, name) then begin
    _file.FindName(name, rec);
    Result := rec;
  end
  else if Length(key) > 4 then begin
    if GetSignatureFromName(key, sig) then
      Result := _file.GroupBySignature[sig]
    else begin
      _file.FindEditorID(key, rec);
      Result := rec;
    end;
  end
  else
    Result := _file.GroupBySignature[StrToSignature(key)];
  if nextPath <> '' then begin
    if Supports(Result, IwbMainRecord, rec) then
      Result := ResolveFromRecord(rec, nextPath)
    else if Supports(Result, IwbGroupRecord, group) then
      Result := ResolveFromGroup(group, nextPath);
  end;
end;

function ResolveFromFile(_file: IwbFile; path: String): IInterface;
var
  key, nextPath: String;
  index: Integer;
begin
  SplitPath(path, key, nextPath);
  // resolve group by index if key is an index
  // else resolve record by formID if key is a formID
  // else resolve by group signature
  if ParseIndex(key, index) then
    Result := ResolveByIndex(_file as IwbContainerElementRef, index, nextPath)
  else if key = 'File Header' then
    Result := ResolveFromRecord(_file.Header, nextPath)
  else 
    Result := ResolveGroupOrRecord(_file, key, nextPath);
end;

function ResolveFile(fileName, nextPath: String): IInterface;
begin
  Result := NativeFileByName(fileName);
  if Assigned(Result) and (nextPath <> '') then
    Result := ResolveFromFile(Result as IwbFile, nextPath);
end;

function ResolveFromRoot(path: String): IInterface;
var
  key, nextPath: String;
  index: Integer;
begin
  SplitPath(path, key, nextPath);
  // resolve file by index if key is an index
  // else resolve by file name
  if ParseIndex(key, index) then
    Result := ResolveByIndex(nil, index, nextPath)
  else 
    Result := ResolveFile(key, nextPath);
end;

function ResolveElement(e: IInterface; path: String): IInterface;
var
  _file: IwbFile;
  group: IwbGroupRecord;
  rec: IwbMainRecord;
  container: IwbContainerElementRef;
begin
  Result := nil;
  if Supports(e, IwbFile, _file) then
    Result := ResolveFromFile(_file, path)
  else if Supports(e, IwbGroupRecord, group) then
    Result := ResolveFromGroup(group, path)
  else if Supports(e, IwbMainRecord, rec) then
    Result := ResolveFromRecord(rec, path)
  else if Supports(e, IwbContainerElementRef, container) then
    Result := ResolveFromContainer(container, path);
end;

function ResolveElementEx(e: IInterface; path: String): IInterface;
begin
  Result := ResolveElement(e, path);
  if not Assigned(Result) then
    raise Exception.Create('Failed to resolve element at path: ' + path);
end;

function NativeGetElement(_id: Cardinal; key: PWideChar): IInterface;
begin
  if string(key) = '' then
    Result := Resolve(_id)
  else if _id = 0 then
    Result := ResolveFromRoot(string(key))
  else
    Result := ResolveElement(Resolve(_id), string(key));
end;

function NativeGetElementEx(_id: Cardinal; key: PWideChar): IwbElement;
var
  e: IInterface;
begin
  e := NativeGetElement(_id, key);
  if not Supports(e, IwbElement, Result) then
    raise Exception.Create('Failed to resolve element at path: ' + string(key));
end;
{$endregion}

{$region 'Element creation'}
function AddGroupIfMissing(_file: IwbFile; sig: String): IwbGroupRecord;
var
  _sig: TwbSignature;
begin
  _sig := TwbSignature(sig);
  if _file.HasGroup(_sig) then
    Result := _file.GroupBySignature[_sig]
  else
    Supports(_file.Add(sig), IwbGroupRecord, Result);
end;

function CreateFromContainer(container: IwbContainerElementRef; path: String): IInterface;
var
  key, nextPath: String;
  index: Integer;
  nextContainer: IwbContainerElementRef;
begin
  SplitPath(path, key, nextPath);
  // . corresponds to appending a new element
  // ^ corresponds to inserting an element at an index, e.g. ^3 inserts at index 3
  // else we get element at key/create it if missing
  if (key = '') or (key = '.') then
    Result := container.Assign(High(Integer), nil, false)
  else if key[1] = '^' then begin
    Result := container.Assign(High(Integer), nil, false);
    index := StrToInt(Copy(key, 2, Length(key) - 1));
    NativeMoveArrayItem(Result as IwbElement, index);
  end
  else begin
    Result := container.ElementByPath[key];
    if not Assigned(Result) then
      Result := container.Add(key);
  end;
  // recurse for next path if present
  if Assigned(Result) and (nextPath <> '') then begin
    if not Supports(Result, IwbContainerElementRef, nextContainer) then
      raise Exception.Create('Failed to traverse into ' + nextPath);
    Result := CreateFromContainer(nextContainer, nextPath);
  end;
end;

function CreateChildGroup(rec: IwbMainRecord; nextPath: String): IInterface;
begin
  Result := rec.EnsureChildGroup;
  if Assigned(Result) and (nextPath <> '') then
    Result := CreateFromGroup(Result as IwbGroupRecord, nextPath);
end;

function CreateFromRecord(rec: IwbMainRecord; path: String): IInterface;
var
  key, nextPath: String;
begin
  SplitPath(path, key, nextPath);
  if SameText(key, 'Child Group') then
    Result := CreateChildGroup(rec, nextPath)
  else
    Result := CreateFromContainer(rec as IwbContainerElementRef, path);
end;

procedure OverrideRecordIfNecessary(rec: IwbMainRecord; targetFile: IwbFile; var output: IInterface);
begin
  if Assigned(rec) and not rec._File.Equals(targetFile) then
    output := CopyElementToFile(rec, targetFile, false, true);
end;

function CreateRecord(group: IwbGroupRecord; formID: Cardinal; nextPath: String): IInterface; overload;
var
  sig: TwbSignature;
  rec: IwbMainRecord;
begin
  sig := TwbSignature(group.GroupLabel);
  Result := group._File.RecordByFormID[formID, true];
  if not Supports(Result, IwbMainRecord, rec) then exit;
  if rec.Signature <> sig then
    raise Exception.Create(Format('Found record %s does not match expected ' +
      'signature %s.', [(Result as IwbMainRecord).Name, string(sig)]));
  OverrideRecordIfNecessary(rec, group._File, Result);
  if nextPath <> '' then
    Result := CreateFromRecord(Result as IwbMainRecord, nextPath);
end;

function CreateGroupOrRecord(group: IwbGroupRecord; key, nextPath: String): IInterface; overload;
var
  innerGroup: IwbGroupRecord;
  rec: IwbMainRecord;
begin
  if key = '.' then
    key := String(AnsiString(group.GroupLabel));
  if Length(key) > 4 then begin
    Result := FindRecordOrGroup(group, key);
    if not Assigned(Result) then
      Result := group.AddGroup(key);
  end
  else
    Result := group.Add(key);
  if nextPath <> '' then begin
    if Supports(Result, IwbGroupRecord, innerGroup) then
      Result := CreateFromGroup(innerGroup, nextPath)
    else if Supports(Result, IwbMainRecord, rec) then
      Result := CreateFromRecord(Result as IwbMainRecord, nextPath);
  end;
end;

function CreateFromGroup(group: IwbGroupRecord; path: String): IInterface;
var
  key, nextPath: String;
  formID: Cardinal;
begin
  SplitPath(path, key, nextPath);
  // resolve/override record by formID
  // else create new group/main record
  if ParseFormID(key, formID) then
    Result := CreateRecord(group, formID, nextPath)
  else
    Result := CreateGroupOrRecord(group, key, nextPath);
end;

function CreateGroup(_file: IwbFile; key: String; nextPath: String): IInterface; overload;
begin
  if Length(key) > 4 then
    key := NativeSignatureFromName(key);
  Result := AddGroupIfMissing(_file, key);
  if Assigned(Result) and (nextPath <> '') then
    Result := CreateFromGroup(Result as IwbGroupRecord, nextPath);
end;

function CreateRecord(_file: IwbFile; formID: Cardinal; nextPath: String): IInterface; overload;
var
  rec: IwbMainRecord;
begin
  Result := _file.RecordByFormID[formID, true];
  if not Supports(Result, IwbMainRecord, rec) then exit;
  OverrideRecordIfNecessary(rec, _file, Result);
  if Assigned(Result) and (nextPath <> '') then
    Result := CreateFromRecord(Result as IwbMainRecord, nextPath);
end;

function CreateFromFile(_file: IwbFile; path: String): IInterface;
var
  key, nextPath: String;
  formID: Cardinal;
begin
  SplitPath(path, key, nextPath);
  // resolve record by formID if key is a formID
  // else resolve file header
  // else resolve by group signature
  if ParseFormID(key, formID) then
    Result := CreateRecord(_file, formID, nextPath)
  else if key = 'File Header' then
    Result := CreateFromRecord(_file.Header, nextPath)
  else
    Result := CreateGroup(_file, key, nextPath);
end;

function CreateFile(fileName, nextPath: String): IInterface;
begin
  Result := NativeFileByName(fileName);
  if not Assigned(Result) then
    Result := NativeAddFile(fileName);
  if Assigned(Result) and (nextPath <> '') then
    Result := CreateFromFile(Result as IwbFile, nextPath);
end;

function CreateFromRoot(path: String): IInterface;
var
  key, nextPath: String;
begin
  SplitPath(path, key, nextPath);
  Result := CreateFile(key, nextPath);
end;

function CreateElement(e: IInterface; path: String): IInterface;
var
  _file: IwbFile;
  group: IwbGroupRecord;
  rec: IwbMainRecord;
  container: IwbContainerElementRef;
begin
  Result := nil;
  if Supports(e, IwbFile, _file) then
    Result := CreateFromFile(_file, path)
  else if Supports(e, IwbGroupRecord, group) then
    Result := CreateFromGroup(group, path)
  else if Supports(e, IwbMainRecord, rec) then
    Result := CreateFromRecord(rec, path)
  else if Supports(e, IwbContainerElementRef, container) then
    Result := CreateFromContainer(container, path);
end;

function NativeAddElement(_id: Cardinal; key: String): IInterface;
begin
  if _id = 0 then
    Result := CreateFromRoot(key)
  else if key = '' then
    Result := Resolve(_id)   
  else
    Result := CreateElement(Resolve(_id), key);
end;
{$endregion}

{$region 'Multi-element resolution'}
procedure GetFiles(len: PInteger);
var
  i: Integer;
begin
  len^ := High(xFiles) + 1;
  SetLength(resultArray, len^);
  for i := 0 to High(xFiles) do
    resultArray[i] := Store(xFiles[i]);
end;

procedure GetContainerElements(container: IwbContainerElementRef; len: PInteger);
var
  i, n: Integer;
  e: IwbElement;
  g: IwbGroupRecord;
begin
  len^ := container.ElementCount;
  SetLength(resultArray, len^);
  if HideChildGroups then begin
    n := 0;
    for i := 0 to Pred(container.ElementCount) do begin
      e := container.Elements[i];
      if Supports(e, IwbGroupRecord, g) and IsChildGroup(g) then continue;
      resultArray[n] := Store(container.Elements[i]);
      Inc(n);
    end;
    len^ := n;
    SetLength(resultArray, n);
  end
  else
    for i := 0 to Pred(container.ElementCount) do
      resultArray[i] := Store(container.Elements[i]);
end;

procedure GetChildrenElements(element: IInterface; len: PInteger);
var
  container: IwbContainerElementRef;
begin
  if not Supports(element, IwbContainerElementRef, container) then
    raise Exception.Create('Interface must be a container.');
  GetContainerElements(container, len);
end;
{$endregion}

function NativeContainer(element: IwbElement): IwbContainer;
var
  group: IwbGroupRecord;
begin
  if Supports(element, IwbGroupRecord, group) and IsChildGroup(group) then
    Result := group.ChildrenOf as IwbContainer
  else
    Result := element.Container;
  if not Assigned(Result) then
    raise Exception.Create('Could not find container for ' + element.Name);
end;

{$region 'Element matching'}
function ElementValueMatches(element: IwbElement; value: string): WordBool;
var
  formID: Int64;
  rec: IwbMainRecord;
  fullName, v: String;
  e1, e2: Extended;
begin
  Result := False;
  if IsFormID(element) then begin
    if ParseFormIDValue(value, formID) then
      Result := element.NativeValue = formID
    else if Supports(element.LinksTo, IwbMainRecord, rec) then begin
      if ParseFullName(value, fullName) then
        Result := rec.FullName = fullName
      else
        Result := rec.EditorID = value;
    end
  end
  else begin
    v := element.EditValue;
    Result := (TryStrToFloat(value, e1) and TryStrToFloat(v, e2) and (e1 = e2)) or (v = value);
  end;
end;

function NativeElementMatches(element: IwbElement; path, value: string): WordBool;
var
  container: IwbContainerElementRef;
begin
  if path = '' then
    Result := ElementValueMatches(element, value)
  else begin
    if not Supports(element, IwbContainerElementRef, container) then
      raise Exception.Create('Interface must be a container to resolve subpaths.');
    Result := ElementValueMatches(container.ElementByPath[path], value);
  end;
end;
{$endregion}

{$region 'Array item handling'}
function NativeGetArrayItem(container: IwbContainerElementRef; path, value: string): IwbElement;
var
  i: Integer;
begin
  for i := 0 to Pred(container.ElementCount) do begin
    Result := container.Elements[i];
    if NativeElementMatches(Result, path, value) then
      exit;
  end;
  Result := nil;
end;

function NativeGetArrayItemEx(container: IwbContainerElementRef; path, value: string): IwbElement;
begin
  Result := NativeGetArrayItem(container, path, value);
  if not Assigned(Result) then
    raise Exception.Create('Could not find matching array element.');
end;

function NativeAddArrayItem(container: IwbContainerElementRef; path, value: String): IwbElement;
var
  e: IInterface;
begin
  Result := container.Assign(High(Integer), nil, False);
  if value = '' then exit;
  if path = '' then
    SetElementValue(Result, value)
  else begin
    e := ResolveElementEx(Result as IInterface, path);
    SetElementValue(e as IwbElement, value);
  end;
end;

procedure NativeRemoveArrayItem(container: IwbContainerElementRef; path, value: string);
var
  i: Integer;
begin
  for i := 0 to Pred(container.ElementCount) do
    if NativeElementMatches(container.Elements[i], path, value) then begin
      container.RemoveElement(i);
      break;
    end;
end;

procedure NativeMoveArrayItem(element: IwbElement; index: Integer);
var
  container: IwbContainerElementRef;
begin
  container := element.Container as IwbContainerElementRef;
  if not IsArray(container) then
    raise Exception.Create('Cannot move elements in non-array containers.');
  if IsSorted(container) then
    raise Exception.Create('Cannot move elements in sorted arrays.');
  if index > container.IndexOf(element) then
    Dec(index);
  element.Remove;
  container.InsertElement(index, element);
end;
{$endregion}

{$region 'Element copying'}
function CopyElementToFile(const aSource: IwbElement; aFile: IwbFile; aAsNew, aDeepCopy: Boolean): IwbElement;
var
  MainRecord: IwbMainRecord;
  Container: IwbContainer;
  Target: IwbElement;
begin
  Result := nil;
  Container := aSource.Container;
  if Assigned(Container) then begin
    if Supports(Container, IwbMainRecord, MainRecord) then
      Container := MainRecord.HighestOverrideOrSelf[aFile.LoadOrder];
    Target := CopyElementToFile(Container, aFile, False, False)
  end
  else
    Result := aFile;

  if Assigned(Target) then
    Result := Target.AddIfMissing(aSource, aAsNew, aDeepCopy, '', '', '');
end;

function CopyElementToRecord(const aSource: IwbElement; aMainRecord: IwbMainRecord; aAsNew, aDeepCopy: Boolean): IwbElement;
var
  Container: IwbContainer;
  Target: IwbElement;
begin
  Result := nil;

  if Assigned(aSource) and (aSource.ElementType = etMainRecord) then begin
    if not aSource.Equals(aMainRecord) then
      Result := aMainRecord;
    Exit;
  end;

  Container := aSource.Container;
  Assert(Assigned(Container));
  Target := CopyElementToRecord(Container, aMainRecord, False, False);

  if Assigned(Target) then
    Result := Target.AddIfMissing(aSource, aAsNew, aDeepCopy, '', '', '');
end;
{$endregion}

function NativeGetSignatureAllowed(formDef: IwbFormIDChecked; sig: TwbSignature): WordBool;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to Pred(formDef.SignatureCount) do
    if formDef.Signatures[i] = sig then begin
      Result := True;
      exit;
    end;
end;

{$region 'Def/type helpers'}
function IsChildGroup(group: IwbGroupRecord): Boolean;
begin
  Result := group.GroupType in [1,6,7];
end;

{ Returns true if @e is a sorted container }
function IsSorted(e: IwbElement): Boolean;
var
  Container: IwbSortableContainer;
begin
  Result := False;
  if Supports(e, IwbSortableContainer, Container) then
    Result := Container.Sorted;
end;

{ Returns true if @e is a container with struct children }
function HasStructChildren(e: IwbElement): boolean;
var
  Container: IwbContainerElementRef;
begin
  Result := False;
  if Supports(e, IwbContainerElementRef, Container)
  and (Container.ElementCount > 0) then
    Result := GetSmashType(Container.Elements[0]) = stStruct;
end;

function IsArray(element: IwbElement): Boolean;
begin
  Result := GetDefType(element) in [dtSubRecordArray, dtArray];
end;

function IsFormID(element: IwbElement): Boolean;
var
  intDef: IwbIntegerDef;
begin
  Result := Supports(element.ValueDef, IwbIntegerDef, intDef)
    and Supports(intDef.Formater[element], IwbFormID);
end;

function GetFlagsDef(element: IwbElement; var flagsDef: IwbFlagsDef): Boolean;
var
  intDef: IwbIntegerDef;
begin
  Result := Supports(element.ValueDef, IwbIntegerDef, intDef)
    and Supports(intDef.Formater[element], IwbFlagsDef, flagsDef);
end;

function GetDefType(element: IwbElement): TwbDefType;
var
  subDef: IwbSubRecordDef;
begin
  if Supports(element.Def, IwbSubRecordDef, subDef) then
    Result := subDef.Value.DefType
  else
    Result := element.Def.DefType;
end;

function GetSmashType(element: IwbElement): TSmashType;
var
  subDef: IwbSubRecordDef;
  dt: TwbDefType;
  bIsSorted, bHasStructChildren: boolean;
begin
  dt := element.Def.DefType;
  if Supports(element.Def, IwbSubRecordDef, subDef) then
    dt := subDef.Value.DefType;

  case Ord(dt) of
    Ord(dtRecord): Result := stRecord;
    Ord(dtSubRecord): Result := stUnknown;
    Ord(dtSubRecordStruct): Result := stStruct;
    Ord(dtSubRecordUnion): Result := stUnion;
    Ord(dtString): Result := stString;
    Ord(dtLString): Result := stString;
    Ord(dtLenString): Result := stString;
    Ord(dtByteArray): Result := stByteArray;
    Ord(dtInteger): Result := stInteger;
    Ord(dtIntegerFormater): Result := stInteger;
    Ord(dtIntegerFormaterUnion): Result := stInteger;
    Ord(dtFlag): Result := stFlag;
    Ord(dtFloat): Result := stFloat;
    Ord(dtSubRecordArray), Ord(dtArray): begin
      bIsSorted := IsSorted(element);
      bHasStructChildren := HasStructChildren(element);
      if bIsSorted then begin
        if bHasStructChildren then
          Result := stSortedStructArray
        else
          Result := stSortedArray;
      end
      else begin
        if bHasStructChildren then
          Result := stUnsortedStructArray
        else
          Result := stUnsortedArray;
      end;
    end;
    Ord(dtStruct): Result := stStruct;
    Ord(dtUnion): Result := stUnion;
    Ord(dtEmpty): Result := stUnknown;
    Ord(dtStructChapter): Result := stStruct;
    else Result := stUnknown;
  end;
end;
{$endregion}
{$endregion}

{$region 'API functions'}
function HasElement(_id: Cardinal; key: PWideChar; bool: PWordBool): WordBool; cdecl;
var
  e: IInterface;
begin
  Result := False;
  try
    e := NativeGetElement(_id, key);
    bool^ := Assigned(e);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

// Has the functionality of FileByName, FileByIndex, GetFileHeader, GroupBySignature,
// GroupByName, RecordByFormID, RecordByEditorID, RecordByName, RecordByIndex,
// GetChildGroup, ElementByName, ElementByPath, ElementByIndex, and ElementBySignature.
function GetElement(_id: Cardinal; key: PWideChar; _res: PCardinal): WordBool; cdecl;
var
  element: IwbElement;
begin
  Result := False;
  try
    element := NativeGetElementEx(_id, key);
    _res^ := Store(element as IInterface);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function AddElement(_id: Cardinal; key: PWideChar; _res: PCardinal): WordBool; cdecl;
var
  element: IInterface;
begin
  Result := False;
  try
    element := NativeAddElement(_id, string(key));
    if not Assigned(element) then
      raise Exception.Create('Failed to add element at path: ' + string(key));
    _res^ := Store(element);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function RemoveElement(_id: Cardinal; key: PWideChar): WordBool; cdecl;
var
  e: IInterface;
  element: IwbElement;
begin
  Result := False;
  try
    e := NativeGetElement(_id, key);
    if Supports(e, IwbFile) then
      raise Exception.Create('Cannot remove files.');
    if not Supports(e, IwbElement, element) then
      raise Exception.Create('Interface is not an element.');
    element.Remove;
    if key = '' then
      Result := Release(_id)
    else
      Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function RemoveElementOrParent(_id: Cardinal): WordBool; cdecl;
var
  e: IInterface;
  element: IwbElement;
  container: IwbContainer;
begin
  Result := False;
  try
    e := Resolve(_id);
    if Supports(e, IwbFile) or Supports(e, IwbGroupRecord)
    or Supports(e, IwbMainRecord) then
      raise Exception.Create('Interface cannot be a file, group, or main record.');
    if not Supports(e, IwbElement, element) then
      raise Exception.Create('Interface is not an element.');
    container := element.Container;
    while not container.IsElementRemoveable(element) do begin
      if Supports(container, IwbMainRecord) then
        raise Exception.Create('Reached main record - could not remove.');
      if container.IsElementRemoveable(element) then
        break;
      element := container as IwbElement;
      container := element.Container;
    end;
    container.RemoveElement(container.IndexOf(element));
    Result := Release(_id);
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

// returns an array of handles for the elements in a container
function GetElements(_id: Cardinal; key: PWideChar; sortBy: Byte; len: PInteger): WordBool; cdecl;
begin
  Result := False;
  try
    if (_id = 0) and (key = '') then
      GetFiles(len)
    else
      GetChildrenElements(NativeGetElementEx(_id, key), len);
    if sortBy > 0 then
      SortResultArray(sortBy);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function GetLinksTo(_id: Cardinal; key: PWideChar; _res: PCardinal): WordBool; cdecl;
var
  linkedElement: IwbElement;
begin
  Result := False;
  try
    linkedElement := NativeGetElementEx(_id, key).LinksTo;
    if not Assigned(linkedElement) then
      raise Exception.Create('Failed to resolve linked element.');
    _res^ := Store(linkedElement);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function GetElementIndex(_id: Cardinal; index: PInteger): WordBool; cdecl;
var
  element: IwbElement;
  _file: IwbFile;
begin
  Result := False;
  try
    if not Supports(Resolve(_id), IwbElement, element) then
      raise Exception.Create('Interface is not an element.');
    if Supports(element, IwbFile, _file) then
      index^ := IndexOfFile(_file)
    else
      index^ := NativeContainer(element).IndexOf(element);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function GetContainer(_id: Cardinal; _res: PCardinal): WordBool; cdecl;
var
  e: IInterface;
  element: IwbElement;
begin
  Result := False;
  try
    e := Resolve(_id);
    if Supports(e, IwbFile) then
      raise Exception.Create('Cannot call GetContainer on files.');
    if not Supports(e, IwbElement, element) then
      raise Exception.Create('Interface is not an element.');
    _res^ := Store(NativeContainer(element));
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function GetElementFile(_id: Cardinal; _res: PCardinal): WordBool; cdecl;
var
  element: IwbElement;
begin
  Result := False;
  try
    if not Supports(Resolve(_id), IwbElement, element) then
      raise Exception.Create('Interface is not an element.');
    _res^ := Store(element._File);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function GetElementRecord(_id: Cardinal; _res: PCardinal): WordBool; cdecl;
var
  element: IwbElement;
  rec: IwbMainRecord;
begin
  Result := False;
  try
    if not Supports(Resolve(_id), IwbElement, element) then
      raise Exception.Create('Interface is not an element.');
    rec := element.ContainingMainRecord;
    if not Assigned(rec) then
      raise Exception.Create('Element is not contained in a record');
    _res^ := Store(rec);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function ElementCount(_id: Cardinal; count: PInteger): WordBool; cdecl;
var
  container: IwbContainerElementRef;
begin
  Result := False;
  try
    if _id = 0 then
      count^ := Length(xFiles)
    else if Supports(Resolve(_id), IwbContainerElementRef, container) then
      count^ := container.ElementCount
    else
      count^ := 0;
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function ElementEquals(_id, _id2: Cardinal; bool: PWordBool): WordBool; cdecl;
var
  element, element2: IwbElement;
begin
  Result := False;
  try
    if not Supports(Resolve(_id), IwbElement, element) then
      raise Exception.Create('First interface is not an element.');
    if not Supports(Resolve(_id2), IwbElement, element2) then
      raise Exception.Create('Second interface is not an element.');
    bool^ := element.Equals(element2);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function ElementMatches(_id: Cardinal; path, value: PWideChar; bool: PWordBool): WordBool; cdecl;
var
  element: IwbElement;
begin
  Result := False;
  try
    element := NativeGetElementEx(_id, path);
    bool^ := NativeElementMatches(element, '', value);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

{$region 'Array item handling'}
function HasArrayItem(_id: Cardinal; path, subpath, value: PWideChar; bool: PWordBool): WordBool; cdecl;
var
  element: IwbElement;
  container: IwbContainerElementRef;
begin
  Result := False;
  try
    element := NativeGetElementEx(_id, path);
    if not Supports(element, IwbContainerElementRef, container)
    or not IsArray(container) then
      raise Exception.Create('Interface must be an array.');
    bool^ := Assigned(NativeGetArrayItem(container, subpath, value));
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function GetArrayItem(_id: Cardinal; path, subpath, value: PWideChar; _res: PCardinal): WordBool; cdecl;
var
  element: IwbElement;
  container: IwbContainerElementRef;
begin
  Result := False;
  try
    element := NativeGetElementEx(_id, path);
    if not Supports(element, IwbContainerElementRef, container)
    or not IsArray(container) then
      raise Exception.Create('Interface must be an array.');
    _res^ := Store(NativeGetArrayItemEx(container, subpath, value));
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function AddArrayItem(_id: Cardinal; path, subpath, value: PWideChar; _res: PCardinal): WordBool; cdecl;
var
  element: IwbElement;
  container: IwbContainerElementRef;
begin
  Result := False;
  try
    element := NativeGetElementEx(_id, path);
    if not Supports(element, IwbContainerElementRef, container)
    or not IsArray(container) then
      raise Exception.Create('Interface must be an array.');
    _res^ := Store(NativeAddArrayItem(container, subpath, value));
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function RemoveArrayItem(_id: Cardinal; path, subpath, value: PWideChar): WordBool; cdecl;
var
  element: IwbElement;
  container: IwbContainerElementRef;
begin
  Result := False;
  try
    element := NativeGetElementEx(_id, path);
    if not Supports(element, IwbContainerElementRef, container)
    or not IsArray(container) then
      raise Exception.Create('Interface must be an array.');
    NativeRemoveArrayItem(container, subpath, value);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function MoveArrayItem(_id: Cardinal; index: Integer): WordBool; cdecl;
var
  element: IwbElement;
begin
  Result := False;
  try
    if not Supports(Resolve(_id), IwbElement, element) then
      raise Exception.Create('Interface is not an element.');
    NativeMoveArrayItem(element, index);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;
{$endregion}

function CopyElement(_id, _id2: Cardinal; aAsNew: WordBool; _res: PCardinal): WordBool; cdecl;
var
  _file: IwbFile;
  rec: IwbMainRecord;
  element, copy: IwbElement;
begin
  Result := False;
  try
    if not Supports(Resolve(_id), IwbElement, element) then
      raise Exception.Create('Interface is not an element.');
    if Supports(Resolve(_id2), IwbFile, _file) then
      copy := CopyElementToFile(element, _file, aAsNew, True)
    else if Supports(Resolve(_id2), IwbMainRecord, rec) then
      copy := CopyElementToRecord(element, rec, aAsNew, True)
    else
      raise Exception.Create('Second interface must be a file or a main record.');
    if not Assigned(copy) then
      raise Exception.Create('Failed to copy element.');
    _res^ := Store(copy);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function GetSignatureAllowed(_id: Cardinal; sig: PWideChar; bool: PWordBool): WordBool;
var
  element: IwbElement;
  integerDef: IwbIntegerDef;
  formDef: IwbFormIDChecked;
begin
  Result := False;
  try
    if not Supports(Resolve(_id), IwbElement, element) then
      raise Exception.Create('Interface is not an element.');
    if not Supports(element.ValueDef, IwbIntegerDef, integerDef)
    or not Supports(integerDef.Formater[element], IwbFormID) then
      raise Exception.Create('Interface must be able to hold a FormID value.');
    if Supports(integerDef.Formater[element], IwbFormIDChecked, formDef) then
      bool^ := NativeGetSignatureAllowed(formDef, StrToSignature(string(sig)))
    else
      bool^ := true;
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function SortKey(_id: Cardinal; len: PInteger): WordBool; cdecl;
var
  element: IwbElement;
begin
  Result := False;
  try
    if not Supports(Resolve(_id), IwbElement, element) then
      raise Exception.Create('Interface is not an element.');
    resultStr := element.SortKey[False];
    len^ := Length(resultStr);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function ElementType(_id: Cardinal; enum: PByte): WordBool; cdecl;
var
  element: IwbElement;
begin
  Result := False;
  try
    if not Supports(Resolve(_id), IwbElement, element) then
      raise Exception.Create('Interface is not an element.');
    enum^ := Ord(element.ElementType);
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function DefType(_id: Cardinal; enum: PByte): WordBool; cdecl;
var
  element: IwbElement;
begin
  Result := False;
  try
    if not Supports(Resolve(_id), IwbElement, element) then
      raise Exception.Create('Interface is not an element.');
    enum^ := Ord(GetDefType(element));
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;

function SmashType(_id: Cardinal; enum: PByte): WordBool; cdecl;
var
  element: IwbElement;
begin
  Result := False;
  try
    if not Supports(Resolve(_id), IwbElement, element) then
      raise Exception.Create('Interface is not an element.');
    enum^ := Ord(GetSmashType(element));
    Result := True;
  except
    on x: Exception do ExceptionHandler(x);
  end;
end;
{$endregion}

end.
