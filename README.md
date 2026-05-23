# Usage
```
  function Zip(Uncompressed: RawByteString; Filename: String): RawByteString;
  function UnZip(Compressed: RawByteString; Filename: String): RawByteString;

  function Deflate(Uncompressed: RawByteString): RawByteString; //gzdeflate from PHP
  function Inflate(Compressed: RawByteString): RawByteString; //gzinflate from PHP

  function UnGzip(const Compressed: String): String; //gzdecode from PHP
  function GZip(const Uncompressed: AnsiString): AnsiString;

  function Zlib(const UnCompressed: String): String; //gzcompress from PHP
  function UnZlib(const Compressed: String): String; //gzdecompress from PHP

  function Zip(const Buf; BufZize: SizeUInt; Filename: String; var OutBuf): SizeUInt; overload;
```
