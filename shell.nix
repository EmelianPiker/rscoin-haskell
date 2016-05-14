{ nixpkgs ? import <nixpkgs> {}, compiler ? "default" }:

let

  inherit (nixpkgs) pkgs;

  f = { mkDerivation, acid-state, aeson, async, base
      , base64-bytestring, binary, bytestring, cereal, conduit-extra
      , containers, cryptohash, data-default, directory, exceptions
      , filepath, hashable, hslogger, hspec, lens, monad-control
      , monad-loops, MonadRandom, msgpack, msgpack-aeson, msgpack-rpc
      , mtl, optparse-applicative, pqueue, QuickCheck, random, safe
      , safecopy, stdenv, stm, text
      , text-format, time, time-units, transformers, transformers-base
      , tuple, unordered-containers, vector
      , git, zlib, openssh, autoreconfHook
      }:
      mkDerivation {
        pname = "rscoin";
        version = "0.1.0.0";
        src = ./.;
        isLibrary = true;
        isExecutable = true;
        libraryHaskellDepends = [
          acid-state aeson base base64-bytestring binary bytestring cereal
          conduit-extra containers cryptohash data-default directory
          exceptions filepath hashable hslogger lens monad-control
          monad-loops MonadRandom msgpack msgpack-aeson msgpack-rpc mtl
          pqueue QuickCheck random safe safecopy  text
          text-format time time-units transformers transformers-base tuple
          unordered-containers vector 
          autoreconfHook 
        ];
        executableHaskellDepends = [
          acid-state aeson base base64-bytestring binary bytestring cereal
          conduit-extra containers cryptohash data-default directory
          exceptions filepath hashable hslogger hspec lens monad-control
          monad-loops MonadRandom msgpack msgpack-aeson msgpack-rpc mtl
          optparse-applicative pqueue QuickCheck random safe safecopy
           text text-format time time-units
          transformers transformers-base tuple unordered-containers vector
          autoreconfHook
        ];
        testHaskellDepends = [
          async base bytestring containers exceptions hspec lens MonadRandom
          msgpack msgpack-rpc mtl QuickCheck random stm text transformers
          vector  
        ];
        libraryPkgconfigDepends = [ zlib git openssh autoreconfHook ];
        license = stdenv.lib.licenses.gpl3;
      };

  haskellPackages = if compiler == "default"
                       then pkgs.haskellPackages
                       else pkgs.haskell.packages.${compiler};

  drv = haskellPackages.callPackage f {};

in

  if pkgs.lib.inNixShell then drv.env else drv
