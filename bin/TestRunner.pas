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
    
    static comp := new Compiler;
    
    ///Обычная компиляция
    static function GetStdCH(batch: array of string; with_dll: boolean; only32bit: boolean): BatchCompHelper;
    begin
      var bch := new BatchCompHelper;
      bch.batch := batch;
      bch.otp_dir := Concat(TestSuiteDir, PathSep, 'exe');
      
      bch.with_dll := with_dll;
      bch.only32bit := only32bit;
      bch.with_ide := false;
      bch.expect_error := false;
      
      Result := bch;
    end;
    
    ///Компиляция, ожидающая ошибку
    static function GetErrCH(batch: array of string; with_ide: boolean): BatchCompHelper;
    begin
      var bch := new BatchCompHelper;
      bch.batch := batch;
      bch.otp_dir := Concat(TestSuiteDir, PathSep, 'exe');
      
      bch.with_dll := true;
      bch.only32bit := true;
      bch.with_ide := with_ide;
      bch.expect_error := true;
      
      Result := bch;
    end;
    
    procedure Exec;
    begin
      //var comp := new Compiler();
      
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

procedure CompileInBatches(path: string; cib: integer; get_bch: IEnumerable<string> -> BatchCompHelper);
begin
  
  var done := 0;
  var done_lock := new object;
  
  var total := 0;
  var last_otp := System.DateTime.Now;
  var init_done := false;
  
  foreach var batch in
    Directory
    .EnumerateFiles(path, '*.pas')
    .Batch(cib)
  do
  begin
    total += 1;
    System.Threading.Tasks.Task.Create(
      ()->
      try
        //Надо обязательно выполнять в отдельном домене
        //Иначе не выйдет удалить сборки, которые создаёт компилятор
        var ad := System.AppDomain.CreateDomain('TestRunner sub domain for compiling');
        
        ad.DoCallBack(get_bch(batch).Exec);
        
        lock done_lock do
        begin
          var ndone := done + 1;
          var curr_otp := DateTime.Now;
          if (ndone = total) or (init_done and ((curr_otp-last_otp).TotalMilliseconds > 100)) then
          begin
            writeln($'{ndone/total,8:P2}');
            last_otp := curr_otp;
          end;
          done := ndone;
        end;
        
        //Эта строчка удаляет все полученные компилятором сборки
        System.AppDomain.Unload(ad);
      except
        on e: Exception do
        begin
          Writeln('Exception in async compile:');
          Writeln(e);
          if not System.Console.IsOutputRedirected then Readln;
          Halt(-1);
        end
      end
    ).Start;
  end;
  
  writeln($'got {total} batches');
  init_done := true;
  
  while done < total do
    Sleep(10);
  
end;

procedure CompileAll(path: string; cib: integer; with_dll: boolean; only32bit: boolean := false) :=
CompileInBatches(
  path, cib,
  batch->BatchCompHelper.GetStdCH(batch.ToArray, with_dll, only32bit)
);

procedure CompileAllErr(path: string; cib: integer; with_ide: boolean) :=
CompileInBatches(
  path, cib,
  batch->BatchCompHelper.GetErrCH(batch.ToArray, with_ide)
);

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
    
//    if TestCLParam('1') then
//    begin
//      Writeln(NewLine+'Compiling RunTests (main dir)');
//      var LT := DateTime.Now;
//      DeletePCUFiles;
//      ClearExeDir;
//      Writeln('Prepare done');
//      CompileAll(TestSuiteDir, 5, false);
//      Writeln($'Done in {DateTime.Now-LT}');
//    end;
    
    if TestCLParam('2') then
    begin
      Writeln(NewLine+'Compiling CompTests (CompilationSamples dir)');
      var LT := DateTime.Now;
      CopyLibFiles;
      Writeln('Prepare done');
      CompileAll(TSSF('CompilationSamples'), 1, false);
      Writeln($'Done in {DateTime.Now-LT}');
    end;
    
    if TestCLParam('3') then
    begin
      CompileAll(TSSF('units'), 5, false);
      CopyPCUFiles;
      CompileAll(TSSF('usesunits'), 5, false);
      CompileAllErr(TSSF('errors'), 5, false);
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
      
      CompileAll(TestSuiteDir, 5, true);
      writeln('Tests with pabcrtl compiled successfully');
      
      CompileAll(TSSF('pabcrtl_tests'), 5, true);
      RunAllTests(false);
      writeln('Tests with pabcrtl run successfully');
      ClearExeDir;
      
      CompileAll(TestSuiteDir, 5, false,true);
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
      Writeln('Exception in Main:');
      Writeln(e);
      if not System.Console.IsOutputRedirected then Readln;
      Halt(-1);
    end;
  end;
end.