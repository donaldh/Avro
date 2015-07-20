use v6;
use JSON::Tiny;
use Avro::Auxiliary;
use Avro::Schema;

package Avro{

  #======================================
  # Exceptions
  #======================================

  class X::Avro::DecodeFail is Avro::AvroException {
    has Avro::Schema $.schema;
    method message { "Failed to decode "~$!schema.type() }
  }


  #== Role ==============================
  #   * Decoder
  #======================================

  role Decoder {
    method decode(Avro::Schema, IO::Handle --> Mu:D) { * };
  }


  #== Class =============================
  #   * BinaryDecoder
  #======================================

  class BinaryDecoder does Decoder { 

    # integers and longs are encode as variable sized zigzag numbers
    sub decode_long(IO::Handle $handle){
      my @arr = ();
      my int $byte;
      repeat {
        $byte = $handle.read(1).unpack("C");
        push(@arr,$byte);
      } until (($byte +> 7) == 0); 
      return from_zigzag(from_varint(@arr));
    }

    multi submethod decode_schema(Avro::Record $schema, IO::Handle $handle) { 
      my %hash;
      for $schema.fields.list -> $field {
        %hash{$field.name} = self.decode_schema($field.type,$handle);
      }
      return %hash;
    }   

    multi submethod decode_schema(Avro::Array $schema, IO::Handle $handle) { 
      my Int $size = decode_long($handle);
      my @arr = ();
      while $size {
        for (1..$size) -> $i {
          push(@arr,self.decode_schema($schema.items,$handle));  
        }
        $size = decode_long($handle);
      } 
      return @arr
    }   

    multi submethod decode_schema(Avro::Map $schema, IO::Handle $handle) { 
      my Int $size = decode_long($handle);
      my %hash;
      my Avro::Schema $keyschema = Avro::String.new();
      while $size {
        for (1..$size) -> $i {
          my Str $key = self.decode_schema($keyschema,$handle);
          my $data = self.decode_schema($schema.values,$handle);
          %hash{$key} = $data;
        }
        $size = decode_long($handle);
      }
      return %hash;
    }   

    multi submethod decode_schema(Avro::Enum $schema, IO::Handle $handle) { 
      my int $result = decode_long($handle);
      $schema.sym[$result];
    }   

    multi submethod decode_schema(Avro::Union $schema, IO::Handle $handle) { 
      my Int $num = decode_long($handle);
      my Avro::Schema $type = $schema.types[$num];
      self.decode_schema($type,$handle);
    }   

    multi submethod decode_schema(Avro::Fixed $schema, IO::Handle $handle) { 
      my @arr = ();
      for (1..$schema.size) -> $i {
        push(@arr,$handle.read(1).unpack("C").chr);
      }
      @arr.join("");
    }   

    multi submethod decode_schema(Avro::Null $schema, IO::Handle $handle) { 
      #my $r = $handle.read(1).unpack("C"); 
      #if $r == 0 { Any }
      #else { X::Avro::DecodeFail.new(:schema($schema)).throw()  }
      Any 
    }   

    multi submethod decode_schema(Avro::String $schema, IO::Handle $handle) { 
      my int $size = decode_long($handle); 
      my Blob $r = $handle.read($size);
      $r.decode()
    }   

    multi submethod decode_schema(Avro::Bytes $schema, IO::Handle $handle) { 
      my int $size = decode_long($handle); 
      my @arr = ();
      for 1..$size -> $i {
        push(@arr,$handle.read(1).unpack("C").chr);
      }
      @arr.join("");
    }   

    multi submethod decode_schema(Avro::Boolean $schema, IO::Handle $handle) {  
      my $r = $handle.read(1).unpack("C"); 
      given $r {
        when 0  { False }

        when 1  { True }

        default { X::Avro::DecodeFail.new(:schema($schema)).throw()  }
      }
    }   

    multi submethod decode_schema(Avro::Integer $schema, IO::Handle $handle) { 
      decode_long($handle);   
    }   

    multi submethod decode_schema(Avro::Long $schema, IO::Handle $handle) { 
      decode_long($handle);
    }   

    multi submethod decode_schema(Avro::Float $schema, IO::Handle $handle) { 
      my @arr = ();
      for 1..4 -> $i {
        push(@arr,$handle.read(1).unpack("C"));
      }
      from_floatbits(int_from_bytes(@arr));
    }   

    multi submethod decode_schema(Avro::Double $schema, IO::Handle $handle) { 
      my @arr = ();
      for 1..8 -> $i {
        push(@arr,$handle.read(1).unpack("C"));
      }
      from_doublebits(int_from_bytes(@arr));
    }   

    method decode(Avro::Schema $schema, IO::Handle $handle) {  
      # TODO check handle
      #X::Avro::DecodeFail.new(:note("End of file")).throw() if $handle.eof;
      {
        return self.decode_schema($schema,$handle); 
        CATCH { default { X::Avro::DecodeFail.new(:schema($schema)).throw() }}
      }
    };

  };


  #== Class =============================
  #   * JSONDecoder
  #======================================

  class JSONDecoder does Decoder {
  
  
  };

}

