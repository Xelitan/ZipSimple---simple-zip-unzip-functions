unit ZipSimple;

//License: MIT
//Author: www.xelitan.com

{$mode objfpc}

interface

uses
  SysUtils, Classes, Zipper, CRC, zstream;


type
  TZipMemHelper = class
    ZipStream : TMemoryStream;
    OutStream : TMemoryStream;
    procedure OpenInput(Sender: TObject; var AStream: TStream);
    procedure CloseInput(Sender: TObject; var AStream: TStream);
    procedure CreateOut(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
    procedure DoneOut(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
  end;
  
  function DateTimeToUnix(Time: TDateTime): Cardinal;

  //public API
  function Zip(const Uncompressed: RawByteString; const Filename: String): RawByteString;
  function UnZip(const Compressed: RawByteString; const Filename: String): RawByteString;
  function Deflate(const Uncompressed: RawByteString): RawByteString; //gzdeflate from PHP
  function Inflate(const Compressed: RawByteString): RawByteString; //gzinflate from PHP

  function UnGzip(const Compressed: String): String; //gzdecode from PHP
  function GZip(const Uncompressed: AnsiString): AnsiString;
  function Zlib(const UnCompressed: String): String; //gzcompress from PHP
  function UnZlib(const Compressed: String): String; //gzdecompress from PHP

  function Zip(const Buf; BufZize: SizeUInt; const Filename: String; var OutBuf): SizeUInt; overload;

implementation

function DateTimeToUnix(Time: TDateTime): Cardinal;
const
  UnixStartDate: TDateTime = 25569.0; // 1970-01-01
begin
  Result := Round((Time - UnixStartDate) * 86400);
end;

function UnZlib(const Compressed: String): String; //gzdecompress from PHP
const BuffSize = 4096;
var Z: TDecompressionStream;
    Read: Integer;
    Temp: String;
    Str: TStringStream;
begin
  Str := TStringStream.Create(Compressed);
  Z := TDecompressionStream.Create(Str, False);
  SetLength(Temp, BuffSize);
  Result := '';
 
  try
    repeat
      Read := Z.Read(Temp[1], BuffSize);
      Result := Result + Copy(Temp, 1, Read);
    until Read<BuffSize-1;
  finally
    Z.Free;
    Str.Free;
  end;
end;
 

function Zlib(const UnCompressed: String): String; //gzcompress from PHP
const BuffSize = 4096;
var Z: TCompressionStream;
    Read: Integer;
    Temp: AnsiString;
    Str: TStringStream;
    Str2: TStringStream;
begin
  Str := TStringStream.Create('');
  Str2 := TStringStream.Create(UnCompressed);
 
  Z := TCompressionStream.Create(clMax, Str, False);
 
  SetLength(Temp, BuffSize);
  Result := '';
 
  try
    repeat
      Read := Str2.Read(Temp[1], BuffSize);
      Z.Write(Temp[1], Read);
 
    until Read = 0;
  finally
    Z.Free;
    Str2.Free;
  end;
 
  Result := Str.DataString;
  Str.Free;
end;
 

function GZip(const Uncompressed: AnsiString): AnsiString;
 
  procedure AppendByte(var S: AnsiString; B: Byte);
  var
    L: Integer;
  begin
    L := Length(S);
    SetLength(S, L + 1);
    S[L + 1] := AnsiChar(B);
  end;
 
  procedure AppendUInt32LE(var S: AnsiString; Value: Cardinal);
  begin
    AppendByte(S, Byte(Value and $FF));
    AppendByte(S, Byte((Value shr 8) and $FF));
    AppendByte(S, Byte((Value shr 16) and $FF));
    AppendByte(S, Byte((Value shr 24) and $FF));
  end;
 
  function CRC32Of(const S: AnsiString): Cardinal;
  const
    Polynomial = $EDB88320;
  var
    CRC: Cardinal;
    I, J: Integer;
    B: Byte;
  begin
    CRC := $FFFFFFFF;
 
    for I := 1 to Length(S) do
    begin
      B := Byte(S[I]);
      CRC := CRC xor B;
      for J := 0 to 7 do
      begin
        if (CRC and 1) <> 0 then
          CRC := (CRC shr 1) xor Polynomial
        else
          CRC := CRC shr 1;
      end;
    end;
 
    Result := not CRC;
  end;
 
var
  Deflated: TStringStream;
  Input: TStringStream;
  Z: TCompressionStream;
  CRC: Cardinal;
  UnixTime: Cardinal;
begin
  Deflated := TStringStream.Create('');
  try
    Input := TStringStream.Create(String(Uncompressed));
    try
      Z := TCompressionStream.Create(clMax, Deflated, True);
      try
        Z.CopyFrom(Input, 0);
      finally
        Z.Free;
      end;
 
      CRC := CRC32Of(Uncompressed);
      UnixTime := DateTimeToUnix(Now);
 
      Result := '';
 
      // GZIP header (10 bytes)
      AppendByte(Result, $1F);          // ID1
      AppendByte(Result, $8B);          // ID2
      AppendByte(Result, $08);          //CM = deflate
      AppendByte(Result, $00);          // FLG = no extra fields
      AppendUInt32LE(Result, UnixTime); // ModTime
      AppendByte(Result, $02);          // XFL = max compression
      AppendByte(Result, $FF);          // OS = unknown
 
      Result := Result + AnsiString(Deflated.DataString);
 
      // Gzip foot
      AppendUInt32LE(Result, CRC);                      // CRC32 of unpacked data
      AppendUInt32LE(Result, Cardinal(Length(Uncompressed))); // ISIZE mod 2^32
    finally
      Input.Free;
    end;
  finally
    Deflated.Free;
  end;
end;
 
function UnGzip(const Compressed: String): String; //gzdecode from PHP
const BuffSize = 4096;
var Z: TDecompressionStream;
    Read: Integer;
    Temp: String;
    Str: TStringStream;
 
    ID: Word;
    Method: Byte;
    Head: Word;
    Date: Cardinal;
    Flag, OS: Byte;
    Skip: Word;
    Tmp: String;
    Null: Integer;
begin
  Str := TStringStream.Create(Compressed);
 
  ID := Str.ReadWord;
  Method := Str.ReadByte;
  Head := Str.ReadByte;
  Date := Str.ReadDWord;
  Flag := Str.ReadByte;
  OS := Str.ReadByte;
 
  //FEXTRA
  if ((Head shr 2) and 1 = 1) then begin
    Skip := Str.ReadByte;
    Str.Position := Str.Position + Skip;
  end;
 
  //FNAME
  if ((Head shr 3) and 1 = 1) then begin
    Tmp := Str.ReadString(256);
    Null := Pos(chr(0), Tmp);
    Str.Position := Str.Position - Length(Tmp) + Null;
  end;
 
  //FCOMMENT
  if ((Head shr 4) and 1 = 1) then begin
    Tmp := Str.ReadString(256);
    Null := Pos(chr(0), Tmp);
    Str.Position := Str.Position - Length(Tmp) + Null;
  end;
 
  //FHCRC
  if ((Head shr 1) and 1 = 1) then begin
    Str.Position := Str.Position + Skip;
  end;
 
  //https://datatracker.ietf.org/doc/html/rfc1952#page-5
  Z := TDecompressionStream.Create(Str, True);
  SetLength(Temp, BuffSize);
  Result := '';
 
  try
    repeat
      Read := Z.Read(Temp[1], BuffSize);
      Result := Result + Copy(Temp, 1, Read);
    until Read<BuffSize-1;
  finally
    Z.Free;
    Str.Free;
  end;
end;

function Inflate(const Compressed: RawByteString): RawByteString; //gzinflate from PHP
const BuffSize = 4096;
var Z: TDecompressionStream;
    Read: Integer;
    Temp: String;
    Str: TStringStream;
begin
  Str := TStringStream.Create(Compressed);
  Z := TDecompressionStream.Create(Str, True);
  SetLength(Temp, BuffSize);
  Result := '';

  try
    repeat
      Read := Z.Read(Temp[1], BuffSize);
      Result := Result + Copy(Temp, 1, Read);
    until Read<BuffSize-1;
  finally
    Z.Free;
    Str.Free;
  end;
end;

function Deflate(const Uncompressed: RawByteString): RawByteString; //gzdeflate from PHP
const BuffSize = 4096;
var Z: TCompressionStream;
    Read: Integer;
    Temp: String;
    Str: TStringStream;
begin
  Str := TStringStream.Create('');
  Z := TCompressionStream.Create(clfastest, Str, True);
  Result := '';

  try
    Z.Write(Uncompressed[1], Length(Uncompressed));

  finally
    Z.Free;

    Result := Str.DataString;

    Str.Free;
  end;
end;



function Zip(const Buf; BufZize: SizeUInt; const Filename: String; var OutBuf): SizeUInt;

  procedure AddWord(var S: RawByteString; W: Word);
  begin
    S := S + AnsiChar(W and $FF) + AnsiChar(W shr 8);
  end;

  procedure AddDWord(var S: RawByteString; D: LongWord);
  begin
    AddWord(S, D and $FFFF);
    AddWord(S, D shr 16);
  end;

var
  MS: TMemoryStream;
  CS: TCompressionStream;
  Compressed, ZipData, ZipData2, NameBytes: RawByteString;
  Crc, LocalHeaderOffset, CentralDirOffset, CentralDirSize: LongWord;
begin
  Result := 0;
  RawByteString(OutBuf) := '';

  MS := TMemoryStream.Create;
  try
    CS := TCompressionStream.Create(clfastest, MS, True);
    try
      CS.WriteBuffer(Buf, BufZize);
    finally
      CS.Free;
    end;

    SetLength(Compressed, MS.Size);
    MS.Position := 0;

    if MS.Size > 0 then MS.ReadBuffer(Pointer(Compressed)^, MS.Size);
  finally
    MS.Free;
  end;

  NameBytes := RawByteString(Filename);
  Crc := CRC32(0, @Buf, BufZize);

  ZipData := '';
  LocalHeaderOffset := 0;

  AddDWord(ZipData, $04034B50);
  AddWord(ZipData, 20);
  AddWord(ZipData, $0800);
  AddWord(ZipData, 8);
  AddWord(ZipData, 0);
  AddWord(ZipData, 0);
  AddDWord(ZipData, Crc);
  AddDWord(ZipData, Length(Compressed));
  AddDWord(ZipData, BufZize);
  AddWord(ZipData, Length(NameBytes));
  AddWord(ZipData, 0);
  ZipData := ZipData + NameBytes;

  CentralDirOffset := Length(ZipData) + Length(Compressed);

  ZipData2 := '';
  AddDWord(ZipData2, $02014B50);
  AddWord(ZipData2, 20);

  AddWord(ZipData2, 20);
  AddWord(ZipData2, $0800);
  AddWord(ZipData2, 8);
  AddWord(ZipData2, 0);
  AddWord(ZipData2, 0);
  AddDWord(ZipData2, Crc);
  AddDWord(ZipData2, Length(Compressed));
  AddDWord(ZipData2, BufZize);
  AddWord(ZipData2, Length(NameBytes));
  AddWord(ZipData2, 0);

  AddWord(ZipData2, 0);
  AddWord(ZipData2, 0);
  AddWord(ZipData2, 0);
  AddDWord(ZipData2, 0);
  AddDWord(ZipData2, LocalHeaderOffset);
  ZipData2 := ZipData2 + NameBytes;

  CentralDirSize := Length(ZipData2);

  AddDWord(ZipData2, $06054B50);
  AddWord(ZipData2, 0);
  AddWord(ZipData2, 0);
  AddWord(ZipData2, 1);
  AddWord(ZipData2, 1);
  AddDWord(ZipData2, CentralDirSize);
  AddDWord(ZipData2, CentralDirOffset);
  AddWord(ZipData2, 0);

  RawByteString(OutBuf) := ZipData + Compressed + ZipData2;
  Result := Length(RawByteString(OutBuf));
end;

procedure TZipMemHelper.OpenInput(Sender: TObject; var AStream: TStream);
begin
  ZipStream.Position := 0;
  AStream := ZipStream;
end;

procedure TZipMemHelper.CloseInput(Sender: TObject; var AStream: TStream);
begin
  AStream := nil;
end;

procedure TZipMemHelper.CreateOut(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
begin
  OutStream.Clear;
  AStream := OutStream;
end;

procedure TZipMemHelper.DoneOut(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
begin
  AStream := nil;
end;

function StreamToString(S: TStream): RawByteString;
begin
  SetLength(Result, S.Size);
  S.Position := 0;

  if S.Size > 0 then
    S.ReadBuffer(Result[1], S.Size);
end;

procedure StringToStream(const Data: RawByteString; S: TStream);
begin
  S.Size := 0;

  if Length(Data) > 0 then
    S.WriteBuffer(Data[1], Length(Data));

  S.Position := 0;
end;

function Zip(const Uncompressed: RawByteString; const Filename: String): RawByteString;
var
  Z        : TZipper;
  InStream : TMemoryStream;
  OutZip   : TMemoryStream;
begin
  InStream := TMemoryStream.Create;
  OutZip := TMemoryStream.Create;
  Z := TZipper.Create;
  try
    StringToStream(Uncompressed, InStream);

    Z.Entries.AddFileEntry(InStream, Filename);

    Z.SaveToStream(OutZip);

    Result := StreamToString(OutZip);
  finally
    Z.Free;
    OutZip.Free;
    InStream.Free;
  end;
end;

function UnZip(const Compressed: RawByteString; const Filename: String): RawByteString;
var
  U : TUnZipper;
  H : TZipMemHelper;
  List: TSTringList;
begin
  H := TZipMemHelper.Create;
  U := TUnZipper.Create;
  try
    H.ZipStream := TMemoryStream.Create;
    H.OutStream := TMemoryStream.Create;

    StringToStream(Compressed, H.ZipStream);

    U.OnOpenInputStream := @H.OpenInput;
    U.OnCloseInputStream := @H.CloseInput;
    U.OnCreateStream := @H.CreateOut;
    U.OnDoneStream := @H.DoneOut;

    List := TSTringList.Create;
    List.Add(Filename);
    U.UnZipFiles(List);
    List.Free;

    Result := StreamToString(H.OutStream);
  finally
    U.Free;

    H.ZipStream.Free;
    H.OutStream.Free;
    H.Free;
  end;
end;

end.
