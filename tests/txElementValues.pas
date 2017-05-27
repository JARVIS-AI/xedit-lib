unit txElementValues;

interface

  // PUBLIC TESTING INTERFACE
  procedure BuildElementValueTests;

implementation

uses
  Mahogany,
{$IFDEF USE_DLL}
  txImports,
{$ENDIF}
{$IFNDEF USE_DLL}
  xeElements, xeElementValues,
{$ENDIF}
  txMeta, txElements;

procedure BuildElementValueTests;
var
  testFile, block, subBlock, childGroup, persistentGroup, refr, armo, rec, 
  element, keyword, h, c: Cardinal;
  expectedName: String;
  str: PWideChar;
  f: Double;
  i: Integer;
begin
  Describe('Element Values', procedure
    begin
      BeforeAll(procedure
        begin
          GetElement(0, 'xtest-2.esp', @testFile);
          GetElement(testFile, 'ARMO', @armo);
          GetElement(armo, '00012E46', @rec);
          GetElement(rec, 'DNAM', @element);
          GetElement(rec, 'KWDA\[1]', @keyword);
          GetElement(testFile, '00027D1C\Child Group', @childGroup);
          GetElement(testFile, 'CELL\[0]', @block);
          GetElement(block, '[0]', @subBlock);
          GetElement(childGroup, '[0]', @persistentGroup);
          GetElement(testFile, '000170F0', @refr);
          GetMem(str, 4096);
        end);
        
      AfterAll(procedure
        begin
          FreeMem(str, 4096);
        end);
        
      Describe('Name', procedure
        begin
          It('Should resolve file names', procedure
            begin
              ExpectSuccess(Name(testFile, str, 256));
              ExpectEqual(String(str), 'xtest-2.esp', '');
            end);
          Describe('Group names', procedure
            begin
              It('Should resolve top level group names', procedure
                begin
                  ExpectSuccess(Name(armo, str, 256));
                  ExpectEqual(String(str), 'Armor', '');
                end);
              It('Should resolve block names', procedure
                begin
                  ExpectSuccess(Name(block, str, 256));
                  ExpectEqual(String(str), 'Block 0', '');
                end);
              It('Should resolve sub-block names', procedure
                begin
                  ExpectSuccess(Name(subBlock, str, 256));
                  ExpectEqual(String(str), 'Sub-Block 0', '');
                end);
              It('Should resolve child group names', procedure
                begin
                  ExpectSuccess(Name(childGroup, str, 256));
                  expectedName := 'Children of 00027D1C';
                  ExpectEqual(String(str), expectedName, '');
                end);
              It('Should resolve persistent/temporary group names', procedure
                begin
                  ExpectSuccess(Name(persistentGroup, str, 256));
                  expectedName := 'Persistent';
                  ExpectEqual(String(str), expectedName, '');
                end);
            end);
          Describe('Record names', procedure
            begin
              It('Should resolve FULL name, if present', procedure
                begin
                  ExpectSuccess(Name(rec, str, 256));
                  ExpectEqual(String(str), 'Iron Gauntlets', '');
                end);
              It('Should resolve BASE name, if present', procedure
                begin
                  ExpectSuccess(Name(refr, str, 256));
                  expectedName := 'DA09PedestalEmpty "Pedestal" [ACTI:0007F82A]';
                  ExpectEqual(String(str), expectedName, '');
                end);
            end);
          It('Should resolve element names', procedure
            begin
              ExpectSuccess(Name(element, str, 256));
              ExpectEqual(String(str), 'DNAM - Armor Rating', '');
            end);
        end);

      Describe('Path', procedure
        begin
          It('Should resolve file names', procedure
            begin
              ExpectSuccess(Path(testFile, str, 1024));
              ExpectEqual(String(str), 'xtest-2.esp', '');
            end);
          It('Should resolve group signatures', procedure
            begin
              ExpectSuccess(Path(armo, str, 1024));
              ExpectEqual(String(str), 'xtest-2.esp\ARMO', '');
            end);
          It('Should resolve block names', procedure
            begin
              ExpectSuccess(Path(block, str, 1024));
              ExpectEqual(String(str), 'xtest-2.esp\CELL\Block 0', '');
            end);
          It('Should resolve sub-block names', procedure
            begin
              ExpectSuccess(Path(subBlock, str, 1024));
              ExpectEqual(String(str), 'xtest-2.esp\CELL\Block 0\Sub-Block 0', '');
            end);
          It('Should resolve child groups', procedure
            begin
              ExpectSuccess(Path(childGroup, str, 1024));
              ExpectEqual(String(str), 'xtest-2.esp\00027D1C\Child Group', '');
            end);
          It('Should resolve temporary/persistent groups', procedure
            begin
              ExpectSuccess(Path(persistentGroup, str, 1024));
              ExpectEqual(String(str), 'xtest-2.esp\00027D1C\Child Group\Persistent', '');
            end);
          It('Should resolve record FormIDs', procedure
            begin
              ExpectSuccess(Path(refr, str, 1024));
              ExpectEqual(String(str), 'xtest-2.esp\000170F0', '');
            end);
          It('Should resolve element names', procedure
            begin
              ExpectSuccess(Path(element, str, 1024));
              ExpectEqual(String(str), 'xtest-2.esp\00012E46\DNAM - Armor Rating', '');
            end);
          It('Should resolve array element indexes', procedure
            begin
              ExpectSuccess(Path(keyword, str, 1024));
              ExpectEqual(String(str), 'xtest-2.esp\00012E46\KWDA - Keywords\[1]', '');
            end);
        end);
        
      Describe('EditorID', procedure
        begin
          It('Should fail if a file is passed', procedure
            begin
              ExpectFailure(EditorID(testFile, str, 256));
            end);
          It('Should fail if a group is passed', procedure
            begin
              ExpectFailure(EditorID(block, str, 256));
              ExpectFailure(EditorID(subBlock, str, 256));
              ExpectFailure(EditorID(childGroup, str, 256));
              ExpectFailure(EditorID(persistentGroup, str, 256));
              ExpectFailure(EditorID(armo, str, 256));
            end);
          It('Should fail if an element is passed', procedure
            begin
              ExpectFailure(EditorID(element, str, 256));
              ExpectFailure(EditorID(keyword, str, 256));
            end);
          It('Should return EditorID if a record is passed', procedure
            begin
              ExpectSuccess(EditorID(rec, str, 256));
              ExpectEqual(String(str), 'ArmorIronGauntlets', '');
              ExpectSuccess(EditorID(refr, str, 256));
              ExpectEqual(String(str), 'DA09PedestalEmptyRef', '');
            end);
        end);
        
      Describe('Signature', procedure
        begin
          It('Should fail if a file is passed', procedure
            begin
              ExpectFailure(Signature(testFile, str, 256));
            end);
          It('Should fail if an element with no signature is passed', procedure
            begin
              ExpectFailure(Signature(keyword, str, 256));
            end);
          It('Should resolve group signatures', procedure
            begin
              ExpectSuccess(Signature(block, str, 256));
              ExpectEqual(String(str), 'GRUP', '');
              ExpectSuccess(Signature(subBlock, str, 256));
              ExpectEqual(String(str), 'GRUP', '');
              ExpectSuccess(Signature(childGroup, str, 256));
              ExpectEqual(String(str), 'GRUP', '');
              ExpectSuccess(Signature(persistentGroup, str, 256));
              ExpectEqual(String(str), 'GRUP', '');
              ExpectSuccess(Signature(armo, str, 256));
              ExpectEqual(String(str), 'ARMO', '');
            end);
          It('Should resolve record signatures', procedure
            begin
              ExpectSuccess(Signature(rec, str, 256));
              ExpectEqual(String(str), 'ARMO', '');
              ExpectSuccess(Signature(refr, str, 256));
              ExpectEqual(String(str), 'REFR', '');
            end);
          It('Should resolve element signatures', procedure
            begin
              ExpectSuccess(Signature(element, str, 256));
              ExpectEqual(String(str), 'DNAM', '');
            end);
        end);
        
      Describe('FullName', procedure
        begin
          It('Should fail if a file is passed', procedure
            begin
              ExpectFailure(FullName(testFile, str, 256));
            end);
          It('Should fail if a group is passed', procedure
            begin
              ExpectFailure(FullName(block, str, 256));
              ExpectFailure(FullName(subBlock, str, 256));
              ExpectFailure(FullName(childGroup, str, 256));
              ExpectFailure(FullName(persistentGroup, str, 256));
              ExpectFailure(FullName(armo, str, 256));
            end);
          It('Should fail if an element is passed', procedure
            begin
              ExpectFailure(FullName(element, str, 256));
              ExpectFailure(FullName(keyword, str, 256));
            end);
          It('Should fail if a record with no full name is passed', procedure
            begin
              ExpectFailure(FullName(refr, str, 256));
            end);
          It('Should return Full Name if a record is passed', procedure
            begin
              ExpectSuccess(FullName(rec, str, 256));
              ExpectEqual(String(str), 'Iron Gauntlets', '');
            end);
        end);

      Describe('GetValue', procedure
        begin
          It('Should resolve element values', procedure
            begin
              ExpectSuccess(GetValue(element, '', str, 256));
              ExpectEqual(String(str), '10.000000', '');
              ExpectSuccess(GetValue(keyword, '', str, 256));
              ExpectEqual(String(str), 'ArmorHeavy [KYWD:0006BBD2]', '');
            end);
          It('Should resolve element value at path', procedure
            begin
              ExpectSuccess(GetValue(rec, 'OBND\X1', str, 256));
              ExpectEqual(String(str), '-11', '');
              ExpectSuccess(GetValue(rec, 'KWDA\[1]', str, 256));
              ExpectEqual(String(str), 'ArmorHeavy [KYWD:0006BBD2]', '');
              ExpectSuccess(GetValue(rec, 'Female world model\MOD4', str, 256));
              ExpectEqual(String(str), 'Test', '');
            end);
          It('Should fail if path does not exist', procedure
            begin
              ExpectFailure(GetValue(rec, 'Non\Existent\Path', str, 256));
            end);
        end);

      Describe('GetIntValue', procedure
        begin
          It('Should resolve element integer values', procedure
            begin
              GetElement(rec, 'OBND\Y1', @h);
              ExpectSuccess(GetIntValue(h, '', @i));
              ExpectEqual(i, -15, '');
            end);
          It('Should resolve element integer values at paths', procedure
            begin
              ExpectSuccess(GetIntValue(rec, 'OBND\Z1', @i));
              ExpectEqual(i, -1, '');
            end);
          It('Should fail if path does not exist', procedure
            begin
              ExpectFailure(GetIntValue(rec, 'Non\Existent\Path', @i));
            end);
        end);

      Describe('GetUIntValue', procedure
        begin
          It('Should resolve element unsigned integer values', procedure
            begin
              ExpectSuccess(GetUIntValue(keyword, '', @c));
              ExpectEqual(c, $6BBD2, '');
            end);
          It('Should resolve element unsigned integer values at paths', procedure
            begin
              ExpectSuccess(GetUIntValue(rec, 'KWDA\[0]', @c));
              ExpectEqual(c, $424EF, '');
            end);
          It('Should fail if path does not exist', procedure
            begin
              ExpectFailure(GetUIntValue(rec, 'Non\Existent\Path', @c));
            end);
        end);

      Describe('GetFloatValue', procedure
        begin
          It('Should resolve element float values', procedure
            begin
              ExpectSuccess(GetFloatValue(element, '', @f));
              // armor rating is stored at *100 internally, for some reason
              ExpectEqual(f, 1000.0, '');
            end);
          It('Should resolve element float values at paths', procedure
            begin
              ExpectSuccess(GetFloatValue(rec, 'DATA\Weight', @f));
              ExpectEqual(f, 5.0, '');
            end);
          It('Should fail if path does not exist', procedure
            begin
              ExpectFailure(GetFloatValue(rec, 'Non\Existent\Path', @f));
            end);
        end);

      Describe('SetValue', procedure
        begin
          It('Should set element values', procedure
            begin
              ExpectSuccess(SetValue(element, '', '14.100000'));
              ExpectSuccess(GetValue(element, '', str, 256));
              ExpectEqual(String(str), '14.100000', '');
              ExpectSuccess(SetValue(keyword, '', 'ArmorLight [KYWD:0006BBD3]'));
              ExpectSuccess(GetValue(keyword, '', str, 256));
              ExpectEqual(String(str), 'ArmorLight [KYWD:0006BBD3]', '');
            end);
          It('Should set element value at path', procedure
            begin
              ExpectSuccess(SetValue(rec, 'OBND\X1', '-8'));
              ExpectSuccess(GetValue(rec, 'OBND\X1', str, 256));
              ExpectEqual(String(str), '-8', '');
              ExpectSuccess(SetValue(rec, 'KWDA\[0]', 'PerkFistsEbony [KYWD:0002C178]'));
              ExpectSuccess(GetValue(rec, 'KWDA\[0]', str, 256));
              ExpectEqual(String(str), 'PerkFistsEbony [KYWD:0002C178]', '');
              ExpectSuccess(SetValue(rec, 'Female world model\MOD4', 'Armor\Iron\F\GauntletsGND.nif'));
              ExpectSuccess(GetValue(rec, 'Female world model\MOD4', str, 256));
              ExpectEqual(String(str), 'Armor\Iron\F\GauntletsGND.nif', '');
            end);
          It('Should fail if path does not exist', procedure
            begin
              ExpectFailure(SetValue(rec, 'Non\Existent\Path', 'Test'));
            end);
        end);

      Describe('SetIntValue', procedure
        begin
          It('Should set element integer values', procedure
            begin
              GetElement(rec, 'OBND\Y1', @h);
              ExpectSuccess(SetIntValue(h, '', -13));
              ExpectSuccess(GetIntValue(h, '', @i));
              ExpectEqual(i, -13, '');
            end);
          It('Should set element integer values at paths', procedure
            begin
              ExpectSuccess(SetIntValue(rec, 'OBND\Z1', -4));
              ExpectSuccess(GetIntValue(rec, 'OBND\Z1', @i));
              ExpectEqual(i, -4, '');
            end);
          It('Should fail if path does not exist', procedure
            begin
              ExpectFailure(SetIntValue(rec, 'Non\Existent\Path', 1));
            end);
        end);

      Describe('SetUIntValue', procedure
        begin
          It('Should set element unsigned integer values', procedure
            begin
              ExpectSuccess(SetUIntValue(keyword, '', $6BBE2));
              ExpectSuccess(GetUIntValue(keyword, '', @c));
              ExpectEqual(c, $6BBE2, '');
            end);
          It('Should set element unsigned integer values at paths', procedure
            begin
              ExpectSuccess(SetUIntValue(rec, 'KWDA\[0]', $2C177));
              ExpectSuccess(GetUIntValue(rec, 'KWDA\[0]', @c));
              ExpectEqual(c, $2C177, '');
            end);
          It('Should fail if path does not exist', procedure
            begin
              ExpectFailure(SetUIntValue(rec, 'Non\Existent\Path', $10));
            end);
        end);

      Describe('SetFloatValue', procedure
        begin
          It('Should resolve element float values', procedure
            begin
              ExpectSuccess(SetFloatValue(element, '', 1920.0));
              ExpectSuccess(GetFloatValue(element, '', @f));
              // armor rating is stored at *100 internally, for some reason
              ExpectEqual(f, 1920.0, '');
            end);
          It('Should resolve element float values at paths', procedure
            begin
              ExpectSuccess(SetFloatValue(rec, 'DATA\Weight', 7.3));
              ExpectSuccess(GetFloatValue(rec, 'DATA\Weight', @f));
              ExpectEqual(f, 7.3, '');
            end);
          It('Should fail if path does not exist', procedure
            begin
              ExpectFailure(SetFloatValue(rec, 'Non\Existent\Path', 1.23));
            end);
        end);
    end);
end;

end.