require 'thread'

class AhoCorasickMatcher
  attr_reader :root
  private :root

  def initialize(dictionary)
    @root = Node.new

    build_trie(dictionary)
    build_suffix_map
  end

  def match(string)
    matches = []
    string.each_char.reduce(root) do |node, char|
      child = (node || root).search(char.intern)
      next unless child

      matches.push(*child.matches)
      child
    end

    matches
  end

  def create_autolink(string)
    pos = 0
    prestart = -1
    preend = -1
    ret = []

    string.each_char.each_with_index.reduce(root) do |node, (char, cur)|
      child = (node || root).search(char.intern)
      next unless child
      if found = child.matches.max{|a, b| a.length <=> b.length }
        start = cur - found.length + 1
        next if start == prestart or start < preend

        match = ret.last && ret.last.match(/>([^<]+)<\/a>/)
        ret.pop if match && found.include?(match[1])

        ret << Rack::Utils.escape_html(string[pos..start-1])
        ret << create_link(found)
        pos = cur + 1
        prestart = start
        preend = pos
      end
      child
    end
    
    if pos < string.length - 1
      ret << string[pos..-1]
    end

    return ret.join('')
  end

  private
  def create_link(keyword)
    anchor = '<a href="%s">%s</a>' % ["/keyword/#{Rack::Utils.escape_path(keyword)}", Rack::Utils.escape_html(keyword)]
  end

  def build_trie(dictionary)
    dictionary.each do |string|
      string.each_char.reduce(root) do |node, char|
        node.child_or_create(char.intern)
      end.matches << string
    end
  end

  def build_suffix_map
    queue = Queue.new

    root.children.each do |child|
      child.suffix = root
      queue << child
    end

    until queue.empty?
      node = queue.pop
      node.children.each { |child| queue << child }
      node.build_child_suffixes
    end
  end

  class Node
    attr_reader :matches, :child_map, :parent
    attr_accessor :suffix

    def initialize(parent = nil)
      @matches = []
      @child_map = {}
      @parent = parent
    end

    def search(char)
      child_map[char] || (suffix && suffix.search(char))
    end

    def child_or_create(char)
      child_map[char] ||= self.class.new(self)
    end

    def children
      child_map.values
    end

    def root?
      !parent
    end

    def build_child_suffixes
      child_map.each do |char, child|
        failure = find_failure_node(char)
        child_suffix = failure.search(char)

        if child_suffix
          child.suffix = child_suffix
          child.matches.push(*child_suffix.matches)
        elsif failure.root?
          child.suffix = failure
        end
      end
    end

    def find_failure_node(char)
      failure = suffix
      failure = failure.suffix until failure.search(char) || failure.root?

      failure
    end

    def inspect
      format('#<%s:0x%x', self.class.name, object_id << 1)
    end
  end
end
