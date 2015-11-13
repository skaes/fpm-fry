require 'cabin/nice_output'
module FPM; module Fry
  class UI < Struct.new(:out, :err, :logger, :tmpdir)

    def initialize( out = STDOUT, err = STDERR, logger = nil , tmpdir = '/tmp/fpm-fry' )
      logger ||= Cabin::Channel.new.tap{|chan| chan.subscribe(Cabin::NiceOutput.new(out)) }
      FileUtils.mkdir_p( tmpdir )
      super( out, err, logger, tmpdir )
    end

  end
end ; end