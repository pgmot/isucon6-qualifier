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
      child = (node || root).search(char.intern) # char.internで、シンボル化
      next unless child

      matches.push(*child.matches)
      child
    end

    matches
  end

  def create_autolink(string)
    pos = 0
    ret = []
    last_found_node = nil

    string.each_char.each_with_index.reduce(root) do |node, (char, cur)|
      child = (node || root).search(char.intern)

      # childが親ノードに含まれていないとき(= トライ木をたどるのが途絶えたとき)の
      # last_found_node(最新のマッチ情報が含まれる)が最長マッチになるので、
      # それまでの文字列と最長マッチをretに突っ込む。
      if last_found_node && (!child || child.parent != node)
        found = last_found_node.matches.max{|a, b| a.length <=> b.length }
        start = cur - found.length - 1
        ret << Rack::Utils.escape_html(string[pos..start]) if start >= 0
        ret << create_link(found)
        last_found_node = nil
        pos = cur
      end

      next unless child

      # マッチが見つかったら、そのノードを突っ込む
      last_found_node = child if child.matches.length > 0
      next child
    end

    # 一番最後の文字列がマッチしていた場合。上のやつをdo-whileっぽく書けばここは要らないかも。
    if last_found_node
      found = last_found_node.matches.max{|a, b| a.length <=> b.length }
      start = string.length - found.length - 1
      ret << create_link(found)
    elsif pos < string.length
      ret << string[pos..-1]
    end

    return ret.join('')
  end

  private
  def uri(addr = nil, absolute = true, add_script_name = true)
    request = Sinatra::Request.new({"rack.url_scheme" => "http", "SERVER_PORT" => "80", "REQUEST_METHOD" => "GET", "SERVER_NAME" => "13.78.127.3"})

    return addr if addr =~ /\A[A-z][A-z0-9\+\.\-]*:/
    uri = [host = ""]
    if absolute
      host << "http#{'s' if request.secure?}://"
      if request.forwarded? or request.port != (request.secure? ? 443 : 80)
        host << request.host_with_port
      else
        host << request.host
      end
    end
    uri << request.script_name.to_s if add_script_name
    uri << (addr ? addr : request.path_info).to_s
    File.join uri
  end

  def create_link(keyword)
    anchor = '<a href="%s">%s</a>' % [uri("/keyword/#{Rack::Utils.escape_path(keyword)}"), Rack::Utils.escape_html(keyword)]
    # anchor = '<a href="%s">%s</a>' % ["/keyword/#{Rack::Utils.escape_path(keyword)}", Rack::Utils.escape_html(keyword)]
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
          child.matches.push(*child_suffix.matches) # 末尾一致のマッチリストに追加する
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
