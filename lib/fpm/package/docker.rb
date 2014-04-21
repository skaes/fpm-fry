require 'fpm'
require 'fpm/package'

require 'fpm/dockery/client'

class FPM::Package::Docker < FPM::Package

  def initialize( options = {} )
    super()
    if options[:logger]
      @logger = options[:logger]
    end
    if options[:client]
      @client = options[:client]
    end
  end

  def input(name)
    leaves = changes(name)
    leaves.each do |chg|
      next if ignore? chg
      copy(name, chg)
    end
  end

private

  def client
    @client ||= FPM::Dockery::Client.new(logger: @logger)
  end

  def copy(name, chg)
    client.copy(name, chg, staging_path(chg), chown: false)
  end

  def changes(name)
    res = client.agent.get(path: client.url('containers',name,'changes'))
    raise res.reason if res.status != 200
    changes = JSON.parse(res.body)
    return change_leaves(changes)
  end

  def ignore?(chg)
    [
      %r!\A/dev[/\z]!,%r!\A/tmp[/\z]!,'/root/.bash_history','/.bash_history'
    ].any?{|pattern| pattern === chg }
  end

  class Node < Struct.new(:children)

    def initialize
      super(Hash.new{|hsh,key| hsh[key] = Node.new })
    end

    def [](name)
      children[name]
    end

    def leaf?
      children.none?
    end

    def leaves( prefix = '/', &block )
      return to_enum(:leaves, prefix) unless block
      if leaf?
        yield prefix
      else
        children.each do |name, cld|
          cld.leaves( File.join(prefix,name), &block )
        end
      end
      return self
    end

  end

  def change_leaves( changes, &block )
    fs = Node.new
    changes.each do |ch|
      n = fs
      ch['Path'].split('/').each do |part|
        n = n[part]
      end
    end
    return fs.leaves(&block)
  end

end

