require 'singleton'
require 'sinatra/base'
require_relative 'lib/aho2.rb' if File.exist?('./lib/aho2.rb')

class Htmlify
  include Singleton

  def keywords
    return @@keywords ||= File.open('/home/syusui/keywords', 'r+') {|f|
      f.each_line.map{|l| l.strip }
    }
  end

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
  alias :url :uri

  def original(content)
    request = ""
    pattern = keywords().map {|k| Regexp.escape(k) }.join('|')
    kw2hash = {}
    hashed_content = content.gsub(/(#{pattern})/) {|m|
      matched_keyword = $1
      "isuda_#{Digest::SHA1.hexdigest(matched_keyword)}".tap do |hash|
        kw2hash[matched_keyword] = hash
      end
    }
    escaped_content = Rack::Utils.escape_html(hashed_content)
    kw2hash.each do |(keyword, hash)|
      keyword_url = url("/keyword/#{Rack::Utils.escape_path(keyword)}")
      anchor = '<a href="%s">%s</a>' % [keyword_url, Rack::Utils.escape_html(keyword)]
      escaped_content.gsub!(hash, anchor)
    end
    return escaped_content.gsub(/\n/, "<br />\n")
  end

  def aho(content)
    raise unless defined?(:AhoCorasickMatcher)
    aho = AhoCorasickMatcher.new( keywords() )
    escaped_content = aho.create_autolink(content)
    return escaped_content.gsub(/\n/, "<br />\n")
  end

  def match(content)
    aho = AhoCorasickMatcher.new( keywords() )
    return aho.match(content)
  end
end
