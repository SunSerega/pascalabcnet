// Copyright (c) Ivan Bondarev, Stanislav Mihalkovich (for details please see \doc\copyright.txt)
// This code is distributed under the GNU LGPL (for details please see \doc\license.txt)
{$reference Compiler.dll}
{$reference CodeCompletion.dll}
{$reference Errors.dll}
{$reference CompilerTools.dll}
{$reference Localization.dll}
{$reference System.Windows.Forms.dll}

//ToDo issue компилятора заставляющие делать костыли:
// - #1588

uses PascalABCCompiler, System.IO, System.Diagnostics;

var
  PathSep := Path.DirectorySeparatorChar;
  IsNotWin := (System.Environment.OSVersion.Platform = System.PlatformID.Unix) or (System.Environment.OSVersion.Platform = System.PlatformID.MacOSX);
  
  TestSuiteDir := Concat(Path.GetDirectoryName(GetCurrentDir), PathSep, 'TestSuite');
  LibDir := Concat(GetCurrentDir, PathSep, 'Lib');

procedure PauseIfNotRedirected :=
if not System.Console.IsOutputRedirected then System.Console.ReadLine;

{$region Compiling}

type
  [System.Serializable]
  ///Предоставляет метод, компилирующий несколько файлов,
  ///И который можно кидать между доменами
  BatchCompHelper = class
    
    otp_dir: string;
    with_dll, only32bit, with_ide, expect_error: boolean;
    batch: array of string;
    
    static comp := new Compiler;
    static curr_test_id: integer;
    
    ///Обычная компиляция
    static function GetStdCH(batch: array of string; otp_dir: string; with_dll: boolean; only32bit: boolean): BatchCompHelper;
    begin
      var bch := new BatchCompHelper;
      bch.batch := batch;
      bch.otp_dir := otp_dir;
      
      bch.with_dll := with_dll;
      bch.only32bit := only32bit;
      bch.with_ide := false;
      bch.expect_error := false;
      
      Result := bch;
    end;
    
    ///Компиляция, ожидающая ошибку
    static function GetErrCH(batch: array of string; otp_dir: string; with_ide: boolean): BatchCompHelper;
    begin
      var bch := new BatchCompHelper;
      bch.batch := batch;
      bch.otp_dir := otp_dir;
      
      bch.with_dll := true;
      bch.only32bit := true;
      bch.with_ide := with_ide;
      bch.expect_error := true;
      
      Result := bch;
    end;
    
    procedure Exec;
    begin
      
      foreach var fname in batch do
      begin
        curr_test_id += 1;
        if &File.ReadAllText(fname).Contains('//winonly') and IsNotWin then continue;
        
        
        
        var co: CompilerOptions := new CompilerOptions(
          fname,
          CompilerOptions.OutputType.ConsoleApplicaton
        );
        co.Debug := true;
        co.OutputDirectory := otp_dir;
        
        co.UseDllForSystemUnits := with_dll;
        co.RunWithEnvironment := with_ide;
        co.IgnoreRtlErrors := false;
        co.Only32Bit := only32bit;
        
        
        
        comp.Compile(co);
        
        if expect_error then
        begin
          
          if comp.ErrorsList.Count = 0 then
          begin
            System.Console.WriteLine($'Compilation of error sample {fname} in test #{curr_test_id} was successfull');
            PauseIfNotRedirected;
            Halt(-1);
          end else
          foreach var err in comp.ErrorsList do
            //ToDo найти почему без "as object" не работает
            if err as object is Errors.CompilerInternalError then
            begin
              System.Console.WriteLine($'Compilation of {fname} in test #{curr_test_id} failed with internal error{System.Environment.NewLine}{err}');
              PauseIfNotRedirected;
              Halt(-1);
            end;
          
        end else
        if comp.ErrorsList.Count <> 0 then
        begin
          
          System.Console.WriteLine($'Compilation of {fname} in test #{curr_test_id} failed{System.Environment.NewLine}{comp.ErrorsList[0]}');
          PauseIfNotRedirected;
          Halt(-1);
          
        end;
        
        
        
        comp.ErrorsList.Clear();
        comp.Warnings.Clear();
        
      end;
      
    end;
    
  end;

procedure CompileInBatches(path: string; cib: integer; get_bch: IEnumerable<string> -> BatchCompHelper);
begin
  
  var total_files := 0;
  var batches: array of sequence of string :=
    Directory
    .EnumerateFiles(path, '*.pas')
    .Select(
      fname->
      begin
        total_files += 1;
        Result := fname;
      end
    )
    .ToArray
    .Batch(cib)
    .ToArray;
  
  var done := 0;
  var total := batches.Length;
  writeln($'splitted {total_files} files in {total} batches, ~{cib} files each');
  var last_otp := System.DateTime.Now;
  
  BatchCompHelper.curr_test_id := 0;
  
  var enm := IEnumerator&<sequence of string>(IEnumerable&<sequence of string>(batches).GetEnumerator());//ToDo #1588
  while enm.MoveNext do
  begin
    var batch := enm.Current;
    
    //Надо обязательно выполнять в отдельном домене
    //Иначе не выйдет удалить сборки, которые создаёт компилятор
    var ad := System.AppDomain.CreateDomain('TestRunner sub domain for compiling');
    
    ad.DoCallBack(get_bch(batch).Exec);
    
    done += 1;
    var curr_otp := DateTime.Now;
    if (done = total) or ((curr_otp-last_otp).TotalMilliseconds > 100) then
    begin
      writeln($'{done/total,8:P2}');
      last_otp := curr_otp;
    end;
    
    //Эта строчка удаляет все полученные компилятором сборки
    System.AppDomain.Unload(ad);
  end;
  
end;

procedure CompileAllStd(path: string; cib: integer; with_dll: boolean; only32bit: boolean; otp_dir: string) :=
CompileInBatches(
  path, cib,
  batch->BatchCompHelper.GetStdCH(batch.ToArray, otp_dir, with_dll, only32bit)
);
procedure CompileAllStd(path: string; cib: integer; with_dll: boolean; only32bit: boolean := false) :=
CompileAllStd(path, cib, with_dll, only32bit, Concat(TestSuiteDir, PathSep, 'exe'));

procedure CompileAllErr(path: string; cib: integer; with_ide: boolean; otp_dir: string) :=
CompileInBatches(
  path, cib,
  batch->BatchCompHelper.GetErrCH(batch.ToArray, otp_dir, with_ide)
);
procedure CompileAllErr(path: string; cib: integer; with_ide: boolean) :=
CompileAllErr(path, cib, with_ide, Concat(TestSuiteDir, PathSep, 'exe'));

{$endregion Compiling}

{$region Runing}

procedure RunAllTests(redirectIO: boolean);
begin
  var files := Directory.GetFiles(TestSuiteDir + PathSep + 'exe', '*.exe');
  for var i := 0 to files.Length - 1 do
  begin
    var psi := new System.Diagnostics.ProcessStartInfo(files[i]);
    psi.CreateNoWindow := true;
    psi.UseShellExecute := false;
    
    psi.WorkingDirectory := TestSuiteDir + PathSep + 'exe';
		  {psi.RedirectStandardInput := true;
		  psi.RedirectStandardOutput := true;
		  psi.RedirectStandardError := true;}
    var p: Process := new Process();
    p.StartInfo := psi;
    p.Start();
    if redirectIO then
      p.StandardInput.WriteLine('GO');
		  //p.StandardInput.AutoFlush := true;
		  //var p := System.Diagnostics.Process.Start(psi);
    
    while not p.HasExited do
      Sleep(10);
    if p.ExitCode <> 0 then
    begin
      System.Windows.Forms.MessageBox.Show('Running of ' + files[i] + ' failed. Exit code is not 0');
      Halt;
    end;
  end;
end;

procedure RunExpressionsExtractTests;
begin
  CodeCompletion.CodeCompletionTester.Test();  
end;

procedure RunIntellisenseTests;
begin
  PascalABCCompiler.StringResourcesLanguage.CurrentTwoLetterISO := 'ru';
  CodeCompletion.CodeCompletionTester.TestIntellisense(TestSuiteDir + PathSep + 'intellisense_tests');
end;

procedure RunFormatterTests;
begin
  CodeCompletion.FormatterTester.Test();
  var errors := &File.ReadAllText(TestSuiteDir + PathSep + 'formatter_tests' + PathSep + 'output' + PathSep + 'log.txt');
  if not string.IsNullOrEmpty(errors) then
  begin
    System.Windows.Forms.MessageBox.Show(errors + System.Environment.NewLine + 'more info at TestSuite/formatter_tests/output/log.txt');
    Halt;
  end;
end;

{$endregion Runing}

{$region FileMoving}

procedure ClearDirByPattern(dir, pattern: string);
begin
  var files := Directory.GetFiles(dir, pattern);
  for var i := 0 to files.Length - 1 do
  begin
    try
      if Path.GetFileName(files[i]) <> '.gitignore' then
        &File.Delete(files[i]);
    except
    end;
  end;
end;

procedure ClearExeDir;
begin
  ClearDirByPattern(TestSuiteDir + PathSep + 'exe', '*.*');
  ClearDirByPattern(TestSuiteDir + PathSep + 'CompilationSamples', '*.exe');
  ClearDirByPattern(TestSuiteDir + PathSep + 'CompilationSamples', '*.mdb');
  ClearDirByPattern(TestSuiteDir + PathSep + 'CompilationSamples', '*.pdb');
  ClearDirByPattern(TestSuiteDir + PathSep + 'CompilationSamples', '*.pcu');
  ClearDirByPattern(TestSuiteDir + PathSep + 'pabcrtl_tests', '*.exe');
  ClearDirByPattern(TestSuiteDir + PathSep + 'pabcrtl_tests', '*.pdb');
  ClearDirByPattern(TestSuiteDir + PathSep + 'pabcrtl_tests', '*.mdb');
  ClearDirByPattern(TestSuiteDir + PathSep + 'pabcrtl_tests', '*.pcu');
end;

procedure DeletePCUFiles;
begin
  ClearDirByPattern(TestSuiteDir + PathSep + 'usesunits', '*.pcu');
end;

procedure CopyLibFiles;
begin
  var files := Directory.GetFiles(LibDir, '*.pas');
  foreach f: string in files do
  begin
    &File.Copy(f, TestSuiteDir + PathSep + 'CompilationSamples' + PathSep + Path.GetFileName(f), true);
  end;
end;

{$endregion FileMoving}

{$region Misc}

function TestCLParam(par: string): boolean :=
//(ParamCount = 0) or (ParamStr(1) = par);
par = '3';//Debug

function TSSF(dir: string) :=
Concat(TestSuiteDir, PathSep, dir);

{$endregion Misc}

begin
  try
    System.Environment.CurrentDirectory := TestSuiteDir;
    
    {$region CompRunTests}
    if TestCLParam('1') then
    begin
      Writeln;
      Writeln('1) Compiling RunTests (main dir)');
      var LT := DateTime.Now;
      DeletePCUFiles;
      ClearExeDir;
      Writeln('Prepare done');
      CompileAllStd(TestSuiteDir, 30, false);
      Writeln($'Done in {DateTime.Now-LT}');
    end;
    {$endregion CompRunTests}
    
    {$region CompTests}
    if TestCLParam('2') then
    begin
      Writeln;
      Writeln('2) Compiling CompTests (CompilationSamples dir)');
      var LT := DateTime.Now;
      CopyLibFiles;
      Writeln('Prepare done');
      CompileAllStd(TSSF('CompilationSamples'), 5, false);
      Writeln($'Done in {DateTime.Now-LT}');
    end;
    {$endregion CompTests}
    
    {$region CompTests with units}
    if TestCLParam('3') then
    begin
      System.Environment.CurrentDirectory := Concat(TestSuiteDir, PathSep, 'usesunits');
      Writeln;
      Writeln('3) Compiling Tests with units in 2 steps:');
      
      Writeln('1. Compiling units (TestSuite\units)');
      CompileAllStd(TSSF('units'), 15, false, false, System.Environment.CurrentDirectory);
      
      Writeln('2. Compiling uses-units (TestSuite\usesunits)');
      CompileAllStd(TSSF('usesunits'), 15, false);
      
      Writeln('Done');
      System.Environment.CurrentDirectory := TestSuiteDir;
    end;
    {$endregion CompTests with units}
    
    {$region CompErrTests}
    if TestCLParam('4') then
    begin
      Writeln;
      Writeln('4) Compiling error tests');
      CompileAllErr(TSSF('errors'), 15, false);
      Writeln('Done');
    end;
    {$endregion CompErrTests}
    
    {$region RunTests}
    if TestCLParam('5') then
    begin
      RunAllTests(false);
      writeln('5) Tests run successfully');
      ClearExeDir;
      DeletePCUFiles;
    end;
    {$endregion RunTests}
    
    {$region ...}
    if TestCLParam('6') then
    begin
      
      CompileAllStd(TestSuiteDir, 5, true);
      writeln('Tests with pabcrtl compiled successfully');
      
      CompileAllStd(TSSF('pabcrtl_tests'), 5, true);
      RunAllTests(false);
      writeln('Tests with pabcrtl run successfully');
      ClearExeDir;
      
      CompileAllStd(TestSuiteDir, 5, false,true);
      writeln('Tests in 32bit mode compiled successfully');
      RunAllTests(false);
      writeln('Tests in 32bit run successfully');
      
      System.Environment.CurrentDirectory := Path.GetDirectoryName(GetEXEFileName);
      RunExpressionsExtractTests;
      writeln('Intellisense expression tests run successfully');
      
      RunIntellisenseTests;
      writeln('Intellisense tests run successfully');
      
      RunFormatterTests;
      writeln('Formatter tests run successfully');
      
    end;
    {$endregion }
    
    Writeln;
    Writeln('Done testing');
    PauseIfNotRedirected;
    
  except
    on e: Exception do
    begin
      Writeln('Exception in Main:');
      Writeln(e);
      PauseIfNotRedirected;
      Halt(-1);
    end;
  end;
end.