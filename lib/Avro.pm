=begin pod
=head1 Avro
C<Avro> is a minimalistic module that encodes and decode Avro.
It supports JSON and Binary decoding/encoding.
=end pod

use v6;
use JSON::Tiny;
use Avro::Schema;
use Avro::Encode;
use Avro::Decode;
use Avro::Datafile;
use Avro::Auxiliary;


module Avro:ver<0.01> {

  #======================================
  # Schema parser interface
  #======================================

  proto parse-schema($) is export {*}

  multi sub parse-schema(Str $text) {
    my Avro::Schema $s = parse(from-json($text)); 
    CATCH {
      when X::JSON::Tiny::Invalid  {
        # For reasons beyond my comprehension 
        # Perl JSON doesn't accept JSON strings as input
       return parse($text); 
      }

      default { $_.throw();}
    }
    return $s;
  }

  multi sub parse-schema(Associative $hash) {
    return parse($hash);
  }

  multi sub parse-schema(Positional $array) {
    return parse($array);
  }

}

