/// Вспомогательные функции для ML.
///
/// Содержит утилиты, используемые в нескольких модулях,
/// не привязанные к DataFrame или конкретным моделям.
unit MLUtilsABC;

interface

uses LinearAlgebraML;

/// Преобразует вектор меток классов в массив целых чисел.
/// Используется при визуализации и других задачах,
///   где метки должны быть представлены как 0,1,2,...
/// Значения округляются функцией Round, чтобы устранить
///   возможные небольшие численные ошибки 
function LabelsToInts(y: Vector): array of integer;

/// Преобразует массив целых меток в Vector.
function IntsToLabels(a: array of integer): Vector;

/// Кодирует строковые метки классов в целочисленные индексы.
/// Каждому уникальному значению присваивается номер 0,1,2,...
/// Порядок кодирования соответствует порядку первого появления меток.
/// Используется при обучении моделей и визуализации.
function EncodeLabels(labels: array of string): array of integer;

/// Кодирует строковые метки классов в целочисленные индексы.
/// Каждому уникальному значению присваивается номер 0,1,2,...
/// Порядок кодирования соответствует порядку первого появления меток.
/// В параметр classes возвращается массив уникальных значений в порядке кодирования.
/// Используется при обучении моделей и визуализации
function EncodeLabels(labels: array of string; var classes: array of string): array of integer;

/// Кодирует целые метки классов в целочисленные индексы.
/// Каждому уникальному значению присваивается номер 0,1,2,...
/// Порядок кодирования соответствует порядку первого появления меток.
/// В параметр classes возвращается массив уникальных значений в порядке кодирования.
/// Используется при обучении моделей и визуализации
function EncodeLabelsInt(labels: array of integer; var classes: array of integer): array of integer;

/// Преобразует строковые метки классов в целочисленные индексы
///   с использованием заранее заданного массива classes (mapping).
/// classes должен быть получен из EncodeLabels.
/// Если встречается неизвестная метка — выбрасывается исключение.
/// Используется для применения кодирования к тестовым данным (Transform).
function TransformLabels(labels: array of string; classes: array of string): array of integer;

/// Преобразует целочисленные индексы классов обратно в строковые метки.
/// Массив classes задаёт соответствие: classes[i] — имя класса с индексом i.
/// Используется для получения текстовых предсказаний моделей.
function DecodeLabels(y: array of integer; classes: array of string): array of string;

/// Возвращает список уникальных меток классов.
/// Порядок соответствует первому появлению значений во входном массиве.
/// Используется для определения множества классов в задаче классификации.
function UniqueLabels(labels: array of string): array of string;

implementation

uses MLExceptions;

const
  ER_LABELS_NULL =
    'y не может быть nil!!y cannot be nil';
  ER_LABELS_ARRAY_NULL =
    'labels не может быть nil!!labels cannot be nil';
  ER_UNKNOWN_CLASS_IN_TRANSFORM =
    'Неизвестное значение класса "{0}" при преобразовании меток!!Unknown class value "{0}" in TransformLabels';
  ER_LABEL_INDEX_OUT_OF_RANGE =
    'Индекс метки {0} вне диапазона [0, {1})!!Label index {0} is out of range [0, {1})';
   

function LabelsToInts(y: Vector): array of integer;
begin
  if y = nil then
    ArgumentNullError(ER_LABELS_NULL, 'y');

  Result := new integer[y.Length];

  for var i := 0 to y.Length - 1 do
    Result[i] := Round(y[i]);
end;

function IntsToLabels(a: array of integer): Vector;
begin
  if a = nil then
    ArgumentNullError(ER_LABELS_ARRAY_NULL, 'a');

  Result := new Vector(a);
end;

function EncodeLabels(labels: array of string; var classes: array of string): array of integer;
begin
  if labels = nil then
    ArgumentNullError(ER_ARG_NULL, 'labels');

  var classList := new List<string>;
  var map := new Dictionary<string, integer>;

  // собираем классы в порядке первого появления
  for var i := 0 to labels.Length - 1 do
  begin
    var lbl := labels[i];
    if not map.ContainsKey(lbl) then
    begin
      map[lbl] := classList.Count;
      classList.Add(lbl);
    end;
  end;

  // кодируем
  var res := new integer[labels.Length];
  for var i := 0 to labels.Length - 1 do
    res[i] := map[labels[i]];

  classes := classList.ToArray;
  Result := res;
end;

function TransformLabels(labels: array of string; classes: array of string): array of integer;
begin
  if labels = nil then
    ArgumentNullError(ER_ARG_NULL, 'labels');

  var map := new Dictionary<string, integer>;
  for var i := 0 to classes.Length - 1 do
    map[classes[i]] := i;

  var res := new integer[labels.Length];

  for var i := 0 to labels.Length - 1 do
  begin
    var lbl := labels[i];

    if not map.ContainsKey(lbl) then
      Error(ER_UNKNOWN_CLASS_IN_TRANSFORM, lbl);

    res[i] := map[lbl];
  end;

  Result := res;
end;

function EncodeLabels(labels: array of string): array of integer;
begin
  var classes: array of string;
  Result := EncodeLabels(labels, classes);
end;

function EncodeLabelsInt(labels: array of integer; var classes: array of integer): array of integer;
begin
  if labels = nil then
    ArgumentNullError(ER_ARG_NULL, 'labels');

  var classList := new List<integer>;
  var map := new Dictionary<integer, integer>;

  // собираем уникальные значения в порядке первого появления
  for var i := 0 to labels.Length - 1 do
  begin
    var lbl := labels[i];
    if not map.ContainsKey(lbl) then
    begin
      map[lbl] := classList.Count;
      classList.Add(lbl);
    end;
  end;

  // кодируем
  var res := new integer[labels.Length];
  for var i := 0 to labels.Length - 1 do
    res[i] := map[labels[i]];

  classes := classList.ToArray;
  Result := res;
end;

function DecodeLabels(y: array of integer; classes: array of string): array of string;
begin
  var res := new string[y.Length];

  for var i := 0 to y.Length - 1 do
  begin
    var idx := y[i];
  
    if (idx < 0) or (idx >= classes.Length) then
      Error(ER_LABEL_INDEX_OUT_OF_RANGE, idx, classes.Length);
  
    res[i] := classes[idx];
  end;

  Result := res;
end;

function UniqueLabels(labels: array of string): array of string;
begin
  Result := labels.Distinct.ToArray;
end;

end.