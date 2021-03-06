my role IO::Socket {
    has $!PIO;
    has Str $.encoding = 'utf8';
    has $.nl-in is rw = ["\n", "\r\n"];
    has Str:D $.nl-out is rw = "\n";
    has Rakudo::Internals::VMBackedDecoder $!decoder;

    method !ensure-decoder(--> Nil) {
        unless $!decoder.DEFINITE {
            $!decoder := Rakudo::Internals::VMBackedDecoder.new($!encoding);
            $!decoder.set-line-separators($!nl-in);
        }
    }

    # The if bin is true, will return Buf, Str otherwise
    method recv(Cool $limit? is copy, :$bin) {
        fail('Socket not available') unless $!PIO;
        $limit = 65535 if !$limit.DEFINITE || $limit === Inf;
        if $bin {
            nqp::readfh($!PIO, nqp::decont(buf8.new), $limit)
        }
        else {
            self!ensure-decoder();
            my $result = $!decoder.consume-exactly-chars($limit);
            without $result {
                $!decoder.add-bytes(nqp::readfh($!PIO, nqp::decont(buf8.new), 65535));
                $result = $!decoder.consume-exactly-chars($limit);
                without $result {
                    $result = $!decoder.consume-all-chars();
                }
            }
            $result
        }
    }

    method read(IO::Socket:D: Int(Cool) $bufsize) {
        fail('Socket not available') unless $!PIO;
        my int $toread = $bufsize;
        my $res := nqp::readfh($!PIO,buf8.new,$toread);

        while nqp::elems($res) < $toread {
            my $buf := nqp::readfh($!PIO,buf8.new,$toread - nqp::elems($res));
            nqp::elems($buf)
              ?? $res.append($buf)
              !! return $res
        }
        $res
    }

    method nl-in is rw {
        Proxy.new(
            FETCH => { $!nl-in },
            STORE => -> $, $nl-in {
                $!nl-in = $nl-in;
                with $!decoder {
                    .set-line-separators($!nl-in.list);
                }
                $nl-in
            }
        )
    }

    method get() {
        self!ensure-decoder();
        my Str $line = $!decoder.consume-line-chars(:chomp);
        if $line.DEFINITE {
            $line
        }
        else {
            loop {
                my $read = nqp::readfh($!PIO, nqp::decont(buf8.new), 65535);
                $!decoder.add-bytes($read);
                $line = $!decoder.consume-line-chars(:chomp);
                last if $line.DEFINITE;
                if $read == 0 {
                    $line = $!decoder.consume-line-chars(:chomp, :eof);
                    last;
                }
            }
            $line.DEFINITE ?? $line !! Nil
        }
    }

    method lines() {
        gather while (my $line = self.get()).DEFINITE {
            take $line;
        }
    }

    method print(Str(Cool) $string --> True) {
        self.write($string.encode($!encoding));
    }

    method put(Str(Cool) $string --> True) {
        self.print($string ~ $!nl-out);
    }

    method write(Blob:D $buf --> True) {
        fail('Socket not available') unless $!PIO;
        nqp::writefh($!PIO, nqp::decont($buf));
    }

    method close(--> True) {
        fail("Not connected!") unless $!PIO;
        nqp::closefh($!PIO);
        $!PIO := nqp::null;
    }

    method native-descriptor(::?CLASS:D:) {
        nqp::filenofh($!PIO)
    }
}

# vim: ft=perl6 expandtab sw=4
