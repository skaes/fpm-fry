require 'fpm/dockery/tar'
module FPM; module Dockery ; module Source
  class Patched

    class Cache < Struct.new(:package, :tmpdir)
      extend Forwardable

      def_delegators :package, :logger, :file_map

      def update
        ex = Tar::Extractor.new(logger: logger)
        inner = package.inner.build_cache(tmpdir)
        tio = inner.tar_io
        begin
          ex.extract(tmpdir, ::Gem::Package::TarReader.new(tio))
        ensure
          tio.close
        end
        package.patches.each do |patch|
          cmd = ['patch','-p1','-i',patch]
          logger.debug("Running patch",cmd: cmd, dir: tmpdir)
          system(*cmd, chdir: tmpdir, out: :close)
        end
        return self
      end

      def tar_io
        cmd = ['tar','-c','.']
        logger.debug("Running tar",cmd: cmd, dir: tmpdir)
        IO.popen(cmd, chdir: tmpdir)
      end
    end

    attr :inner, :patches

    extend Forwardable

    def_delegators :inner, :logger, :file_map

    def initialize( inner , options = {})
      @inner = inner
      @patches = Array(options[:patches])
    end

    def build_cache(tmpdir)
      Cache.new(self,tmpdir).update
    end

    def self.decorate(options)
      if options.key?(:patches) && Array(options[:patches]).size > 0
        p = options.delete(:patches)
        return new( yield options, patches: p )
      else
        return yield options
      end
    end
  end

end ; end ; end

