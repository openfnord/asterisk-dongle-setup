{ pkgs ? import <nixpkgs> {}
, stdenv ? pkgs.stdenv
}:

let
  python = pkgs.python37Packages;

  local = rec {
    callPackage = pkgs.lib.callPackageWith collection;

    collection = rec {

      mypyps = ppkgs: with ppkgs; [
        pandas
        requests
        pyst2
        ipython
        telethon
      ];

      mypython = pkgs.python37.withPackages mypyps;

      shell = pkgs.mkShell {
        name = "shell";
        buildInputs = [
          pkgs.ccls
          mypython
        ];
      shellHook = with pkgs; ''
        export PYTHONPATH=`pwd`/python:$PYTHONPATH
      '';
      };

      asterisk = pkgs.asterisk_16.overrideAttrs (old: rec {
        pname = old.pname + "-tweaked";

        configureFlags = old.configureFlags ++ [
          "--disable-xmldoc"
        ];
      });

      usb_modeswitch = stdenv.mkDerivation {
        name = "usb_modeswitch";

        buildInputs = with pkgs; [libusb.dev pkgconfig gnumake];

        makeFlags = "DESTDIR=\${out}";

        src = pkgs.fetchurl {
          url = "https://www.draisberghof.de/usb_modeswitch/usb-modeswitch-2.6.0.tar.bz2";
          sha256 = "sha256:18wbbxc5cfsmikba0msdvd5qlaga27b32nhrzicyd9mdddp265f2";
        };
      };

      pyst2 = python.buildPythonPackage rec {
        pname = "pyst2";
        version = "0.5.1";
        propagatedBuildInputs = with python ; [ six ];
        doCheck = false; # due to missing `import SocketServer`
        src = python.fetchPypi {
          inherit pname version;
          sha256 = "sha256:1kw13g7wldzrnnr9vcm97m4c8pv801hl4fl7q88jvz0q9caz9s07";
        };
      };

      telegram_check = python.buildPythonApplication {
        pname = "telegram_check";
        version = "1.0";
        src = ./python;
        pythonPath = with pkgs.python37Packages; [
          telethon
        ];
        doCheck = false;
      };

      asterisk-chan-dongle = stdenv.mkDerivation {
        name = "asterisk-chan-dongle";

        # src = pkgs.fetchgit {
        #   url = "https://github.com/wdoekes/asterisk-chan-dongle";
        #   rev = "0d1bad55b55940cecc9b196c72e17fc254a3d5a7";
        #   sha256 = "sha256:1nvbc5azqgpc7vwyc0mskqxpnrz8a65a37r6n7nisw3r9q7axasy";
        # };

        src = ./asterisk-chan-dongle;

        preConfigure = ''
          ./bootstrap
        '';

        configureFlags = [
          "--with-astversion=${asterisk.version}"
          "--with-asterisk=${asterisk}/include"
          "--with-iconv=${pkgs.libiconv}/include"
          "--enable-debug"
          "--enable-apps"
          "--enable-manager"
          "DESTDIR=${placeholder "out"}"
        ];

        buildInputs = [
          asterisk
          pkgs.autoconf
          pkgs.automake
          pkgs.sqlite
          pkgs.libiconv
        ];
      };

      asterisk-modules = pkgs.symlinkJoin {
        name = "asterisk-modules";
        paths = [ "${asterisk}/lib/asterisk/modules"
                  asterisk-chan-dongle ];
      };



      asterisk-conf = stdenv.mkDerivation {
        name = "asterisk-conf";
        buildCommand = ''
          mkdir -pv $out
          mkdir -pv $out/etc/asterisk
          for f in ${asterisk}/etc/asterisk/* ; do
            cp -R $f $out/etc/asterisk
          done

          sed -i 's@console => notice,warning,error@console => notice,warning,error,debug@g' $out/etc/asterisk/logger.conf

          rm $out/etc/asterisk/asterisk.conf
          cat >$out/etc/asterisk/asterisk.conf <<EOF
          [directories]
          astetcdir => $out/etc/asterisk
          astmoddir => ${asterisk-modules}
          astvarlibdir => ${asterisk}/var/lib/asterisk
          astdbdir => /tmp/asterisk
          astkeydir => ${asterisk}/var/lib/asterisk
          astdatadir => ${asterisk}/var/lib/asterisk
          astagidir => ${asterisk}/var/lib/asterisk/agi-bin
          astspooldir => /tmp/asterisk
          astrundir => /tmp/asterisk/
          astlogdir => /tmp/asterisk/
          astsbindir => ${asterisk}/sbin

          [options]
          verbose = 9
          debug = 0
          runuser = root		; The user to run as.
          rungroup = root		; The group to run as.
          EOF

          # cp -v ${asterisk-chan-dongle.src}/etc/dongle.conf $out/etc/asterisk
          cat >$out/etc/asterisk/dongle.conf <<EOF
          [general]
          interval=15
          ;smsdb=/tmp/asterisk/smsdb
          ;csmsttl=5

          [defaults]
          context=dongle-incoming			; context for incoming calls
          group=0				; calling group
          rxgain=0			; increase the incoming volume; may be negative
          txgain=0			; increase the outgoint volume; may be negative
          autodeletesms=yes		; auto delete incoming sms
          resetdongle=yes			; reset dongle during initialization with ATZ command
          u2diag=-1			; set ^U2DIAG parameter on device (0 = disable everything except modem function) ; -1 not use ^U2DIAG command
          usecallingpres=yes		; use the caller ID presentation or not
          callingpres=allowed_passed_screen ; set caller ID presentation		by default use default network settings
          disablesms=no			; disable of SMS reading from device when received
                            ;  chan_dongle has currently a bug with SMS reception. When a SMS gets in during a
                            ;  call chan_dongle might crash. Enable this option to disable sms reception.
                            ;  default = no

          language=en			; set channel default language
          mindtmfgap=45			; minimal interval from end of previews DTMF from begining of next in ms
          mindtmfduration=80		; minimal DTMF tone duration in ms
          mindtmfinterval=200		; minimal interval between ends of DTMF of same digits in ms

          callwaiting=auto		; if 'yes' allow incoming calls waiting; by default use network settings
                              ; if 'no' waiting calls just ignored
          disable=no			; OBSOLETED by initstate: if 'yes' no load this device and just ignore this section

          initstate=start			; specified initial state of device, must be one of 'stop' 'start' 'remote'
                              ;   'remove' same as 'disable=yes'

          exten=+1234567890		; exten for start incoming calls, only in case of Subscriber Number not available!, also set to CALLERID(ndid)

          dtmf=relax			; control of incoming DTMF detection, possible values:
                          ;   off	   - off DTMF tones detection, voice data passed to asterisk unaltered
                          ;              use this value for gateways or if not use DTMF for AVR or inside dialplan
                          ;   inband - do DTMF tones detection
                          ;   relax  - like inband but with relaxdtmf option
                          ;  default is 'relax' by compatibility reason

          [dongle0]
          data=/dev/ttyUSB0		; tty port for AT commands; 		no default value
          audio=/dev/ttyUSB1		; tty port for audio connection; 	no default value
          context=dongle-incoming			; context for incoming calls
          language=ru			; set channel default language
          smsaspdu=yes

          ; or you can omit both audio and data together and use imei=123456789012345 and/or imsi=123456789012345
          ;  imei and imsi must contain exactly 15 digits !
          ;  imei/imsi discovery is available on Linux only
          ;imei=123456789012345
          ;imsi=123456789012345
          EOF

          rm $out/etc/asterisk/extensions.conf
          cat >$out/etc/asterisk/extensions.conf <<"EOF"
          [general]

          [dongle-incoming]
          exten => sms,1,Verbose(Incoming SMS)
          exten => sms,n,Hangup()
          EOF
        '';
      };

    };
  };

in
  local.collection
