// Copyright (c) Ivan Bondarev, Stanislav Mihalkovich (for details please see \doc\copyright.txt)
// This code is distributed under the GNU LGPL (for details please see \doc\license.txt)
{$reference Compiler.dll}
{$reference CodeCompletion.dll}
{$reference Errors.dll}
{$reference CompilerTools.dll}
{$reference Localization.dll}
{$reference System.Windows.Forms.dll}

uses PascalABCCompiler, System.IO, System.Diagnostics;

var
  PathSep := Path.DirectorySeparatorChar;
  IsNotWin := (System.Environment.OSVersion.Platform = System.PlatformID.Unix) or (System.Environment.OSVersion.Platform = System.PlatformID.MacOSX);
  
  TestSuiteDir := Concat(Path.GetDirectoryName(GetCurrentDir), PathSep, 'TestSuite');
  LibDir := Concat(GetCurrentDir, PathSep, 'Lib');

{$region Compiling}

type
  [System.Serializable]
  ///Предоставляет метод, компилирующий несколько файлов,
  ///И который можно кидать между доменами
  BatchCompHelper = class
    
    otp_dir: string;
    with_dll, only32bit, with_ide, expect_error: boolean;
    batch: array of string;
    
    ///Обычная компиляция
    static function GetStdMethod(batch: array of string; with_dll: boolean; only32bit: boolean := false): System.CrossAppDomainDelegate;
    begin
      var bch := new BatchCompHelper;
      bch.batch := batch;
      bch.otp_dir := Concat(TestSuiteDir, PathSep, 'exe');
      
      bch.with_dll := with_dll;
      bch.only32bit := only32bit;
      bch.with_ide := false;
      bch.expect_error := false;
      
      Result := bch.Exec;
    end;
    
    ///Компиляция, ожидающая ошибку
    static function GetErrMethod(batch: array of string; with_ide: boolean): System.CrossAppDomainDelegate;
    begin
      var bch := new BatchCompHelper;
      bch.batch := batch;
      bch.otp_dir := Concat(TestSuiteDir, PathSep, 'exe');
      
      bch.with_dll := true;
      bch.only32bit := true;
      bch.with_ide := with_ide;
      bch.expect_error := true;
      
      Result := bch.Exec;
    end;
    
    procedure Exec;
    begin
      var comp := new Compiler();
      
      foreach var fname in batch do
      begin
        if &File.ReadAllText(fname).Contains('//winonly') and IsNotWin then continue;
        
        
        
        var co: CompilerOptions := new CompilerOptions(fname, CompilerOptions.OutputType.ConsoleApplicaton);
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
            System.Console.WriteLine($'Compilation of error sample {fname} was successfull');
            Halt(-1);
          end else
          foreach var err in comp.ErrorsList do
            //ToDo найти почему без "as object" не работает
            if err as object is Errors.CompilerInternalError then
            begin
              System.Console.WriteLine($'Compilation of {fname} failed with internal error{System.Environment.NewLine}{err}');
              Halt(-1);
            end;
          
        end else
        if comp.ErrorsList.Count <> 0 then
        begin
          
          System.Console.WriteLine($'Compilation of {fname} failed{System.Environment.NewLine}{comp.ErrorsList[0]}');
          Halt(-1);
          
        end;
        
        
        
        comp.ErrorsList.Clear();
        comp.Warnings.Clear();
        
      end;
      
    end;
    
  end;

procedure CompileAll(path: string; with_dll: boolean; only32bit: boolean := false);
begin
  
  foreach var _batch in Directory.EnumerateFiles(path, '*.pas').Batch(30) do
  begin
    var batch := _batch.ToArray;
    //Надо обязательно выполнять в отдельном домене
    //Иначе не выйдет удалить сборки, которые создаёт компилятор
    var ad := System.AppDomain.CreateDomain('TestRunner sub domain for compiling');
    
    ad.DoCallBack(
      BatchCompHelper.GetStdMethod(
        batch,
        with_dll, only32bit
      )
    );
    
    //Эта строчка удаляет все полученные компилятором сборки
    System.AppDomain.Unload(ad);
  end;
  
end;

procedure CompileAllErr(path: string; with_ide: boolean);
begin
  
  foreach var _batch in Directory.EnumerateFiles(path, '*.pas').Batch(30) do
  begin
    var batch := _batch.ToArray;
    var ad := System.AppDomain.CreateDomain('TestRunner sub domain for compiling');
    
    ad.DoCallBack(
      BatchCompHelper.GetErrMethod(
        batch,
        with_ide
      )
    );
    
    System.AppDomain.Unload(ad);
  end;
  
end;

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

procedure CopyPCUFiles;
begin
  System.Environment.CurrentDirectory := Path.GetDirectoryName(GetEXEFileName());
  var files := Directory.GetFiles(TestSuiteDir + PathSep + 'units', '*.pcu');
  
  foreach fname: string in files do
  begin
    &File.Move(fname, TestSuiteDir + PathSep + 'usesunits' + PathSep + Path.GetFileName(fname));
  end;
end;

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
(ParamCount = 0) or (ParamStr(1) = par);

function TSSF(dir: string) :=
Concat(TestSuiteDir, PathSep, dir);

{$endregion Misc}

begin
  try
    
    //readln;
    System.Environment.CurrentDirectory := TestSuiteDir;
    
    if TestCLParam('1') then
    begin
      DeletePCUFiles;
      ClearExeDir;
      CompileAll(TestSuiteDir, false);
      Writeln('Done compiling RunTests (main dir)');
    end;
    
    
    if TestCLParam('2') then
    begin
      CopyLibFiles;
      CompileAll(TSSF('CompilationSamples'), false);
      Writeln('Done compiling CompTests (CompilationSamples dir)');
    end;
    
    if TestCLParam('3') then
    begin
      CompileAll(TSSF('units'), false);
      CopyPCUFiles;
      CompileAll(TSSF('usesunits'), false);
      CompileAllErr(TSSF('errors'), false);
      writeln('Done with units and ErrTests');
    end;
    
    if TestCLParam('4') then
    begin
      RunAllTests(false);
      writeln('Tests run successfully');
      ClearExeDir;
      DeletePCUFiles;
    end;
    
    if TestCLParam('5') then
    begin
      
      CompileAll(TestSuiteDir, true);
      writeln('Tests with pabcrtl compiled successfully');
      
      CompileAll(TSSF('pabcrtl_tests'), true);
      RunAllTests(false);
      writeln('Tests with pabcrtl run successfully');
      ClearExeDir;
      
      CompileAll(TestSuiteDir, false,true);
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
    
    if not System.Console.IsOutputRedirected then Readln;
    
  except
    on e: Exception do
    begin
      Writeln('Exception:');
      Writeln(e);
      if not System.Console.IsOutputRedirected then Readln;
      Halt(-1);
    end;
  end;
end.