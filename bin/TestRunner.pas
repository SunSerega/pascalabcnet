// Copyright (c) Ivan Bondarev, Stanislav Mihalkovich (for details please see \doc\copyright.txt)
// This code is distributed under the GNU LGPL (for details please see \doc\license.txt)
{$reference Compiler.dll}
{$reference CodeCompletion.dll}
{$reference Errors.dll}
{$reference CompilerTools.dll}
{$reference Localization.dll}
{$reference System.Windows.Forms.dll}

//ToDo 7+)

uses PascalABCCompiler, System.IO, System.Diagnostics;

{$region $define настройки}

//Если раскомментировано - выполняет только выбранную группу тестов
{$define SpecTestGroup}
{$ifdef SpecTestGroup}
  ///id тестовой группы те же самые, что и те, что можно вбить в командную строку
  ///но SpecTestGroup перезаписывает аргументы командной строки
  ///Так же id показывает при выполнении, к примеру, для тестовой группы "3":
  ///3) Compiling Tests with units in 2 steps:
  var SpecTestGroups := Arr&<string>('6');
  
  //Если раскомментировано - выполняет только выбранный тест и группы выше
  { $define SpecTest}
  {$ifdef SpecTest}
    ///id теста показывает когда в нём вылетает ошибка. Пишет:
    ///"{ЧтоДелало} of "{имя файла}" in test #{id этого теста} {что именно пошло не так}"
    ///К примеру:
    ///Compilation of "D:\TestSuite\MyTestName.pas" in test #123 failed
    var SpecTestId := 45;
  {$endif SpecTest}
  
{$endif SpecTestGroup}

//Если раскомментировано - ждёт нажатия Enter перед выходом. Включая и выход из за ошибки, и выход по завершению
{$define NeedPause}

{$endregion $define настройки}

{$region Misc}

var
  PathSep := Path.DirectorySeparatorChar;
  IsNotWin := (System.Environment.OSVersion.Platform = System.PlatformID.Unix) or (System.Environment.OSVersion.Platform = System.PlatformID.MacOSX);
  
  TestSuiteDir := Concat(Path.GetDirectoryName(GetCurrentDir), PathSep, 'TestSuite');
  LibDir := Concat(GetCurrentDir, PathSep, 'Lib');
  
  curr_test_id: integer;

procedure PauseIfNeeded :=
{$ifdef NeedPause}
  System.Console.ReadLine;
{$else NeedPause}
  exit;
{$endif NeedPause}

function IsTestGroupActive(par: string): boolean :=
{$ifndef SpecTestGroup}//Not
  (CommandLineArgs.Length = 0) or CommandLineArgs.Contains(par);
{$else SpecTestGroup}
  SpecTestGroups.Contains(par);
{$endif SpecTestGroup}

///Возвращает полное имя данной подпапки, находящейся в папке "TestSuite"
function TSSF(dir: string) :=
Concat(TestSuiteDir, PathSep, dir);

procedure WritePstDone(ST: DateTime; var LT: DateTime; pst: real; min_milliseconds: real := 300);
begin
  var CT := DateTime.Now;
  if (pst < 0.999) and ((CT-LT).TotalMilliseconds < min_milliseconds) then exit;
  
  var left := System.TimeSpan.MaxValue;
  try
    var spend := CT-ST;
    left := new System.TimeSpan(
      System.Convert.ToInt64(
        spend.Ticks/pst
      )
    ) - spend;
  except end;
  
  writeln($'{pst,8:P2} | time left: {left} | ready at {CT+left:T}');
  LT := CT;
end;

{$endregion Misc}

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
      //var comp :=         Compiler(System.AppDomain.CurrentDomain.GetData('comp'));
      var comp := new Compiler;//ToDo очень медленно, но чтоб передавать между доменами надо чтоб всё содержимое Compiler было сериализуемо
      
      var curr_test_id := integer(System.AppDomain.CurrentDomain.GetData('curr_test_id'));
      
      foreach var fname in batch do
      begin
        curr_test_id += 1;
        
        {$ifdef SpecTest}
          var SpecTestId := integer(System.AppDomain.CurrentDomain.GetData('SpecTestId'));
          
          if curr_test_id=SpecTestId then
            System.Console.WriteLine($'Executing only Test #{SpecTestId},{NewLine}Which is: Compiling of file "{fname}"') else
            continue;
        {$endif SpecTest}
        
        if &File.ReadAllText(fname).Contains('//winonly') and IsNotWin then 
          {$ifndef SpecTest}//Not
            continue;
          {$else}
            if curr_test_id=SpecTestId then
              System.Console.WriteLine($'Warning! Test #{SpecTestId} was only suited for Windows!') else
              continue;
          {$endif SpecTest}
        
        
        
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
            System.Console.WriteLine($'Compilation of error sample "{fname}" in test #{curr_test_id} was successfull');
            PauseIfNeeded;
            Halt(-1);
          end else
          foreach var err in comp.ErrorsList do
            //ToDo найти почему без "as object" не работает
            if err as object is Errors.CompilerInternalError then
            begin
              System.Console.WriteLine($'Compilation of "{fname}" in test #{curr_test_id} failed with internal error{NewLine}{err}');
              PauseIfNeeded;
              Halt(-1);
            end;
          
        end else
        if comp.ErrorsList.Count <> 0 then
        begin
          
          System.Console.WriteLine($'Compilation of "{fname}" in test #{curr_test_id} failed{System.Environment.NewLine}{comp.ErrorsList[0]}');
          PauseIfNeeded;
          Halt(-1);
          
        end;
        
        
        
        comp.ErrorsList.Clear();
        comp.Warnings.Clear();
        
        {$ifdef SpecTest}
          System.Console.WriteLine($'SpecTest exection was successfull, done testing');
          PauseIfNotRedirected;
          Halt(0);
        {$endif SpecTest}
        
      end;
      
      //System.AppDomain.CurrentDomain.SetData('curr_test_id', curr_test_id);
    end;
    
  end;

procedure CompileInBatches(path: string; cib: integer; get_bch: IEnumerable<string> -> BatchCompHelper);
begin
  //var comp := new Compiler;
  
  var total_files := 0;
  var batches: sequence of sequence of string :=
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
    .Batch(cib);
  
  writeln($'splitted {total_files} files in { (total_files-1) div cib + 1} batches, ~{cib} files each');
  
  
  var ST := DateTime.Now;
  var last_otp := DateTime.Now;
  
  foreach var batch in batches do
  begin
    
    //Надо обязательно выполнять в отдельном домене
    //Иначе не выйдет удалить сборки, которые создаёт компилятор
    var ad := System.AppDomain.CreateDomain('TestRunner sub domain for compiling');
    
    //ad.SetData('comp', comp);//Не получается. Это было бы на много быстрее, но компилятор не умеет сериализовываться
    ad.SetData('curr_test_id', curr_test_id);
    {$ifdef SpecTest}
      ad.SetData('SpecTestId', SpecTestId);
    {$endif SpecTest}
        
    
    ad.DoCallBack(get_bch(batch).Exec);
    
    //curr_test_id := integer(ad.GetData('curr_test_id'));
    curr_test_id += batch.Count;
    
    WritePstDone(ST, last_otp, curr_test_id/total_files);
    
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
  
  var ST := DateTime.Now;
  var last_otp := DateTime.Now;
  var done := 0;
  foreach var fname in files do
  begin
    curr_test_id += 1;
    
    var psi := new ProcessStartInfo(fname);
    psi.CreateNoWindow := true;
    psi.UseShellExecute := false;
    psi.WorkingDirectory := TSSF('exe');
    if redirectIO then
    begin
		  psi.RedirectStandardInput := true;
		  psi.RedirectStandardOutput := true;
		  psi.RedirectStandardError := true;
    end;
    
		var p := Process.Start(psi);
		
    if redirectIO then
      p.StandardInput.WriteLine('GO');
    
    p.WaitForExit(3000);
    if p.ExitCode <> 0 then
    begin
      Writeln($'Runing of "{fname}" in test #{curr_test_id} failed, exit code is {p.ExitCode}');
      PauseIfNeeded;
      Halt(-1);
    end;
    
    if redirectIO then
    begin
      var otp := p.StandardOutput.ReadToEnd;
      if otp<>'' then
      begin
        writeln($'Reading output of "{fname}" in test #{curr_test_id} wasn''t empty. It was:');
        writeln(otp);
        writeln($'--- End output of test #{curr_test_id} ---');
      end;
    end;
    
    done += 1;
    WritePstDone(ST, last_otp, done/files.Length);
    
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

{$region FileMoving/Deleting}

procedure ClearDirByPattern(dir, pattern: string) :=
foreach var fname in Directory.EnumerateFiles(dir, pattern) do
  try
    if Path.GetFileName(fname) <> '.gitignore' then
      &File.Delete(fname);
  except
    on e: Exception do
    begin
      Writeln($'Warning: can''t delete {fname}:');
      Writeln(e);
    end;
  end;

procedure ClearExeDirs;
begin
  ClearDirByPattern(TSSF('exe'), '*.*');
  ClearDirByPattern(TSSF('CompilationSamples'), '*.exe');
  ClearDirByPattern(TSSF('CompilationSamples'), '*.mdb');
  ClearDirByPattern(TSSF('CompilationSamples'), '*.pdb');
  ClearDirByPattern(TSSF('CompilationSamples'), '*.pcu');
  ClearDirByPattern(TSSF('pabcrtl_tests'), '*.exe');
  ClearDirByPattern(TSSF('pabcrtl_tests'), '*.pdb');
  ClearDirByPattern(TSSF('pabcrtl_tests'), '*.mdb');
  ClearDirByPattern(TSSF('pabcrtl_tests'), '*.pcu');
end;

procedure DeletePCUFromUsesUnits :=
ClearDirByPattern(TSSF('usesunits'), '*.pcu');

procedure CopyLibFilesToTests :=
foreach var fname in Directory.EnumerateFiles(LibDir, '*.pas') do
  &File.Copy(fname, Concat( TSSF('CompilationSamples'), PathSep, Path.GetFileName(fname) ), true);

{$endregion FileMoving/Deleting}

begin
  try
    
    System.Environment.CurrentDirectory := TestSuiteDir;
    
    if IsTestGroupActive(#0) then
      Writeln('Running all 6 tests') else
    begin
      Writeln('Warning: Running not all tests');
      {$ifdef SpecTestGroup}
        Writeln($'Running only test groups: {SpecTestGroups.JoinIntoString('', '')}');
      {$else SpecTestGroup}
        Writeln($'Running only test groups: {CommandLineArgs.JoinIntoString('', '')}');
      {$endif SpecTestGroup}
    end;
    
    var ST := DateTime.Now;
    ClearExeDirs;
    
    {$region 1) CompRunTests }
    if IsTestGroupActive('1') then
    begin
      curr_test_id := 0;
      Writeln;
      Writeln('1) Compiling RunTests (main dir)');
      var LT := DateTime.Now;
      
      Writeln('Prepare done');
      
      CompileAllStd(TestSuiteDir, 30, false);
      
      Writeln($'Done in {DateTime.Now-LT}');
    end;
    {$endregion 1) CompRunTests}
    
    {$region 2) CompTests }
    if IsTestGroupActive('2') then
    begin
      curr_test_id := 0;
      Writeln;
      Writeln('2) Compiling CompTests (CompilationSamples dir)');
      var LT := DateTime.Now;
      
      CopyLibFilesToTests;
      Writeln('Prepare done');
      
      CompileAllStd(TSSF('CompilationSamples'), 5, false, false, TSSF('CompilationSamples'));
      
      Writeln($'Done in {DateTime.Now-LT}');
    end;
    {$endregion 2) CompTests}
    
    {$region 3) CompTests with units }
    if IsTestGroupActive('3') then
    begin
      curr_test_id := 0;
      Writeln;
      Writeln('3) Compiling Tests with units in 2 steps:');
      DeletePCUFromUsesUnits;
      System.Environment.CurrentDirectory := TSSF('usesunits');
      var LT := DateTime.Now;
      
      Writeln('1. Compiling units (TestSuite\units)');
      CompileAllStd(TSSF('units'), 15, false, false, TSSF('usesunits'));
      
      Writeln('2. Compiling uses-units (TestSuite\usesunits)');
      CompileAllStd(TSSF('usesunits'), 15, false);
      
      DeletePCUFromUsesUnits;
      Writeln($'Done in {DateTime.Now-LT}');
      System.Environment.CurrentDirectory := TestSuiteDir;
    end;
    {$endregion 3) CompTests with units}
    
    {$region 4) CompErrTests }
    if IsTestGroupActive('4') then
    begin
      curr_test_id := 0;
      Writeln;
      Writeln('4) Compiling error tests');
      var LT := DateTime.Now;
      
      CompileAllErr(TSSF('errors'), 15, false);
      
      Writeln($'Done in {DateTime.Now-LT}');
    end;
    {$endregion 4) CompErrTests}
    
    {$region 5) RunTests }
    if IsTestGroupActive('5') then
    begin
      curr_test_id := 0;
      Writeln;
      Writeln('5) Runing tests');
      var LT := DateTime.Now;
      
      RunAllTests(false);
      
      Writeln('Cleaning up');
      ClearExeDirs;
      DeletePCUFromUsesUnits;
      
      Writeln($'Done in {DateTime.Now-LT}');
    end;
    {$endregion 5) RunTests}
    
    {$region 6) PABCRtlTests }
    if IsTestGroupActive('6') then
    begin
      ClearExeDirs;
      curr_test_id := 0;
      Writeln;
      Writeln('6) PABCRtlTests in 2 steps:');
      var LT := DateTime.Now;
      
      Writeln('1. Compiling PABCRtlTests');
      CompileAllStd(TSSF('pabcrtl_tests'), 5, true);
      
      Writeln('2. Running PABCRtlTests');
      RunAllTests(false);
      
      ClearExeDirs;
      Writeln($'Done in {DateTime.Now-LT}');
    end;
    {$endregion 6) PABCRtlTests}
    
    {$region 7) }
    if IsTestGroupActive('7') then
    begin
      ClearExeDirs;
      curr_test_id := 0;
      Writeln;
      Writeln('7) ');
      var LT := DateTime.Now;
      
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
    
    Writeln($'Making sure everything is cleaned up');
    DeletePCUFromUsesUnits;
    ClearExeDirs;
    
    Writeln($'Done testing in {DateTime.Now-ST}');
    PauseIfNeeded;
    
  except
    on e: Exception do
    begin
      Writeln('Exception in Main:');
      Writeln(e);
      PauseIfNeeded;
      Halt(-1);
    end;
  end;
end.