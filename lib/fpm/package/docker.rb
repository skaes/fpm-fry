require 'fpm'
require 'fpm/package'
require 'fpm/fry/channel'

require 'fpm/fry/client'

# An {FPM::Package} that loads files from a docker container diff.
class FPM::Package::Docker < FPM::Package

  attr_reader :logger, :client, :keep_modified_files

  # @param [Hash] options
  # @option options [Cabin::Channel] :logger Logger
  # @option options [FPM::Fry::Client] :client Docker client
  def initialize( options = {} )
    super()
    @logger = options[:logger] || Cabin::Channel.get
    @client = options[:client] || FPM::Fry::Client.new(logger: @logger)
    @keep_modified_files = options[:keep_modified_files]
    @verbose = options[:verbose]
  end

  # Loads all files from a docker container with the given name to the staging
  # path.
  #
  # @param [String] name docker container name
  def input(name)
    split( name, '**' => staging_path)
  end

  # Loads all files from a docker container into multiple paths defined by map
  # param.
  #
  # @param [String] name docker container name
  # @param [Hash<String,String>] map
  def split( name, map )
    changes = changes(name)
    changes.remove_modified_leaves!(changes_to_remove) do | kind, ml |
      if kind == DELETED
        logger.warn("Found a deleted file. You can't delete files as part of a package.", name: ml)
      elsif !keep_modified_files
        logger.warn("Found a modified file. You can't modify files in a package.", name: ml)
      end
    end
    fmap = {}
    changes.leaves.each do | change |
      map.each do | match, to |
        if File.fnmatch?(match, change)
          fmap[change] = File.join(to, change)
          break
        end
      end
    end
    directories = changes.smallest_superset
    directories.each do |chg|
      client.copy(name, chg, fmap, chown: false)
    end
    return nil
  end

  private

  def changes(name)
    client_changes = client.changes(name)
    if @verbose
      names = {MODIFIED => "MOD", CREATED => "ADD", DELETED => "DEL"}
      client_changes.each do |change|
        puts [names[change["Kind"]], change["Path"]].join(" ")
      end
    end
    fs = Node.read(client_changes)
    fs.reject!(&method(:ignore?))
    return fs
  end

  def copy(name, chg, options = {})
    client.copy(name, chg, staging_path(chg), {chown: false}.merge(options))
  end

  IGNORED_PATTERNS = [
    %r!\A/dev(/|\z)!,%r!\A/tmp(/|\z)!,'/root/.bash_history','/.bash_history'
  ]

  def ignore?(chg)
    return true if IGNORED_PATTERNS.any?{|pattern| pattern === chg }
    Array(attributes[:excludes]).each do |wildcard|
      if File.fnmatch(wildcard, chg) || File.fnmatch(wildcard, chg[1..-1])
        return true
      end
    end
    return false
  end

  MODIFIED = 0
  CREATED = 1
  DELETED = 2

  def changes_to_remove
    @keep_modified_files ? [DELETED] : [DELETED, MODIFIED]
  end

  # @api private
  class Node < Struct.new(:children, :kind)

    def initialize
      super(Hash.new{|hsh,key| hsh[key] = Node.new },nil)
    end

    def [](name)
      children[name]
    end

    def leaf?
      children.none?
    end

    def leaves(prefix = '/', &block)
      return to_enum(:leaves, prefix) unless block
      if leaf?
        yield prefix, false
      else
        children.each do |name, cld|
          cld.leaves( File.join(prefix,name), &block )
        end
      end
      return self
    end

    def contains_leaves?
      children.any?{|_,c| c.leaf? }
    end

    def modified_leaves(prefix = '/', &block)
      return to_enum(:modified_leaves, prefix) unless block
      if leaf?
        if kind != CREATED
          yield kind, prefix
        end
      else
        children.each do |name, cld|
          cld.modified_leaves( File.join(prefix,name), &block)
        end
      end
    end

    def remove_modified_leaves!(changes_to_remove, prefix = '/', &block)
      to_remove = {}
      children.each do |name, cld|
        removed_children = cld.remove_modified_leaves!(changes_to_remove, File.join(prefix,name), &block)
        if cld.leaf? && changes_to_remove.include?(cld.kind)
          to_remove[name] = [cld.kind, removed_children]
        end
      end
      if to_remove.any?
        to_remove.each do |name, (kind, removed_children)|
          children.delete(name)
          if !removed_children
            yield kind, File.join(prefix,name)
          end
        end
        return true
      end
      return false
    end

    def smallest_superset(prefix = '/', &block)
      return to_enum(:smallest_superset, prefix) unless block
      if leaf?
        return
      elsif contains_leaves?
        yield prefix
      else
        children.each do |name, cld|
          cld.smallest_superset( File.join(prefix,name), &block)
        end
      end
    end

    def reject!(prefix = '/', &block)
      children.reject! do |name, cld|
        p = File.join(prefix,name)
        if yield p
          true
        else
          cld.reject!(p,&block)
          false
        end
      end
    end

    def delete(path)
      _, key, rest = path.split('/',3)
      if rest.nil?
        children.delete(key)
      else
        children[key].delete("/#{rest}")
      end
    end

    def self.read(enum)
      fs = Node.new
      enum.each do |ch|
        n = fs
        ch['Path'].split('/').each do |part|
          n = n[part]
        end
        n.kind = ch['Kind']
      end
      return fs
    end
  end

end

