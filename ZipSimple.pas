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

  //public API
  function Zip(Uncompressed: RawByteString; Filename: String): RawByteString;
  function UnZip(Compressed: RawByteString; Filename: String): RawByteString;
  function Deflate(Uncompressed: RawByteString): RawByteString; //gzdeflate from PHP
  function Inflate(Compressed: RawByteString): RawByteString; //gzinflate from PHP

  function Zip(const Buf; BufZize: SizeUInt; Filename: String; var OutBuf): SizeUInt; overload;

implementation


function Inflate(Compressed: RawByteString): RawByteString; //gzinflate from PHP
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

function Deflate(Uncompressed: RawByteString): RawByteString; //gzdeflate from PHP
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



function Zip(const Buf; BufZize: SizeUInt; Filename: String; var OutBuf): SizeUInt;

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

function Zip(Uncompressed: RawByteString;
  Filename: String): RawByteString;
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

function UnZip(Compressed: RawByteString;
  Filename: String): RawByteString;
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
