use v6;
use JSON::Tiny;
use Avro::Auxiliary;
use Avro::Encode;
use Avro::Decode;
use Avro::Schema;

package Avro { 

  #======================================
  # Exceptions
  #======================================

  class X::Avro::DataFileWriter is Avro::AvroException {
    has Str $.note;
    method message { "Failed to write to Data File, "~$!note }
  }

  class X::Avro::DataFileReader is Avro::AvroException {
    has Str $.note;
    method message { "Failed to read Data File, "~$!note }
  }

  
  #======================================
  #   Package variables and constants
  #======================================

  my Avro::Record $schema_h = parse(
    {"type"=> "record", "name"=> "org.apache.avro.file.Header",
     "fields" => [
      {"name"=> "magic", "type"=> {"type"=> "fixed", "name"=> "Magic", "size"=> 4}},
      {"name"=> "meta", "type"=> {"type"=> "map", "values"=> "bytes"}},
      {"name"=> "sync", "type"=> {"type"=> "fixed", "name"=> "Sync", "size"=> 16}}]});

  my Avro::Fixed $fixed_s = parse({"type"=> "fixed", "name"=> "Sync", "size"=> 16});

  constant magic = "Obj\x01";


  #== Enum ==============================
  #   * Encoding
  #   -- the output type, used by the 
  #   constructors of reader and writer
  #======================================

  enum Encoding <JSON Binary>; 


  #== Enum ==============================
  #   * Codec
  #   -- the codec, used by the writer
  #======================================

  enum Codec <null deflate>;


  #== Class =============================
  #   * DataFileWriter
  #======================================

  class DataFileWriter {

    constant DefaultBlocksize = 10240; 

    has IO::Handle $!handle;
    has Avro::Encoder $!encoder;
    has Avro::Schema $!schema;
    has Codec $!codec;
    has Blob $!syncmark;
    has List $!buffer;
    has Int $!blocksize;
    has Int $!buffersize;
    has Int $!count;

    multi method new(IO::Handle :$handle!, Avro::Schema :$schema!, Encoding :$encoding? = Encoding::Binary, 
      Associative :$metadata? = {}, Codec :$codec? = Codec::null, Int :$blocksize? = DefaultBlocksize) {

      my Avro::Encoder $encoder;
      given $encoding {
        when Encoding::JSON   { $encoder = Avro::JSONEncoder.new() }
        when Encoding::Binary { $encoder = Avro::BinaryEncoder.new() }
      }
      
      self.bless(handle => $handle, schema => $schema, encoder => $encoder,
        metadata => $metadata, codec => $codec, blocksize => $blocksize );
    }

    submethod BUILD(IO::Handle :$handle!, Avro::Schema :$schema!, Avro::Encoder :$encoder!,
      Associative :$metadata, Codec :$codec, Int :$blocksize) {

      my @rands = (0..255).map: { $_.chr }; # byte range
      my @range = (1..16);
      my $sync = (@range.map:{ @rands.pick(1) }).join("");
      $!syncmark = pop ($encoder.encode($fixed_s,$sync));
      $!buffersize = 0;
      $!count = 0;
      $!handle = $handle;
      $!schema = $schema;
      $!blocksize = $blocksize;
      $!encoder = $encoder;
      my %metahash = 'avro.schema' => $schema.to_json(), 'avro.codec' => ~$codec;
      %metahash.push( $metadata.kv ) if $metadata.kv.elems() != 0;
      my %header =  magic => magic, sync => $sync, meta => %metahash;
      write_list($!handle,$!encoder.encode($schema_h,%header)); #todo switch based on encoding ?
    }

    method append(Mu $data){
      my @data = $!encoder.encode($!schema,$data);
      my $size = bytes_list(@data);  
      self!write_block if ($!buffersize + $size) > $!blocksize; 
      $!count++;
      $!buffersize += $size;
      push $!buffer, @data;
    }

    method !write_block {
      return unless $!buffersize > 0;
      write_list($!handle,$!encoder.encode(Avro::Long.new(),$!count)); 
      write_list($!handle,$!encoder.encode(Avro::Long.new(),$!buffersize));
      write_list($!handle,$!buffer);
      $!handle.write($!syncmark);
      $!buffersize = 0;
      $!count = 0;
      $!buffer = ().List;
    }

    method close {
      self!write_block;
      $!handle.close
    }

  }


  #== Class =============================
  #   * DataFileReader
  #======================================

  class DataFileReader {

    has IO::Handle $!handle;
    has Avro::Decoder $!decoder;
    has Avro::Schema $.schema;
    has Codec $.codec;
    has Str $.syncmark;
    has Associative $.meta;

    multi method new(IO::Handle :$handle!, Encoding :$encoding? = Encoding::Binary) {
      my Avro::Decoder $decoder; 
      given $encoding {
        when Encoding::JSON   { $decoder = Avro::JSONDecoder.new() }
        when Encoding::Binary { $decoder = Avro::BinaryDecoder.new() }
      }
      self.bless(handle => $handle, decoder => $decoder);
    }

    submethod BUILD(IO::Handle :$handle, Avro::Decoder :$decoder!){
      $!handle = $handle;
      $!decoder = $decoder;
      my %header = $decoder.decode($schema_h,$handle);
      X::Avro::DataFileReader.new(:note("Incorrect magic bytes")).throw() 
        unless %header{'magic'} ~~ magic;
      $!syncmark = %header{'sync'};
      my %meta = %header{'meta'}.kv;
      $!schema =  parse(from-json(%meta{'avro.schema'})); #TODO fix json lib string problem?
      %meta<avro.schema>:delete;
      given %meta{'avro.codec'} {
        when 'null' { $!codec = Codec::null }
        when 'deflate' { $!codec = Codec::deflate }
        default {  X::Avro::DataFileReader.new(:note("Unsupported codec: $_")).throw() }
      }
      %meta<avro.codec>:delete;
      $!meta = %meta;
    }

    method !read_block() {
      my Int $count = $!decoder.decode(Avro::Long.new(),$!handle);
      my Int $size  = $!decoder.decoder(Avro::Long.new(),$!handle);
    }

    method read() { 
      return $!decoder.decode($!schema,$!handle); 
    }

    method slurp() { * }

  }

}
