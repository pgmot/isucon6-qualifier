require 'digest/sha1'
require 'json'
require 'net/http'
require 'uri'

require 'erubis'
require 'mysql2'
require 'mysql2-cs-bind'
require 'rack/utils'
require 'sinatra/base'
require 'tilt/erubis'

require 'redis'
require_relative './../aho2.rb'

module Isuda
  class Web < ::Sinatra::Base
    enable :protection
    enable :sessions

    set :erb, escape_html: true
    set :public_folder, File.expand_path('../../../../public', __FILE__)
    set :db_user, ENV['ISUDA_DB_USER'] || 'root'
    set :db_password, ENV['ISUDA_DB_PASSWORD'] || ''
    set :dsn, ENV['ISUDA_DSN'] || 'dbi:mysql:db=isuda'
    set :session_secret, 'tonymoris'
    set :isupam_origin, ENV['ISUPAM_ORIGIN'] || 'http://localhost:5050'
    set :isutar_origin, ENV['ISUTAR_ORIGIN'] || 'http://localhost:5001'

    configure :development do
      require 'sinatra/reloader'

      register Sinatra::Reloader
    end

    set(:set_name) do |value| # User idと名前を取ってくるだけ。@user_id, @user_name
      condition {
        user_id = session[:user_id]
        if user_id
          user = db.xquery(%| select name from user where id = ? |, user_id).first
          @user_id = user_id
          @user_name = user[:name]
          halt(403) unless @user_name
        end
      }
    end

    set(:authenticate) do |value| # @user_idに何も入ってなかったら,403
      condition {
        halt(403) unless @user_id
      }
    end

    helpers do
      def db # こいつは、db.xqueryのdbの部分。DBが何もなかったら、作る処理してる。
        Thread.current[:db] ||=
          begin
            _, _, attrs_part = settings.dsn.split(':', 3)
            attrs = Hash[attrs_part.split(';').map {|part| part.split('=', 2) }]
            mysql = Mysql2::Client.new(
              username: settings.db_user,
              password: settings.db_password,
              database: attrs['db'],
              encoding: 'utf8mb4',
              init_command: %|SET SESSION sql_mode='TRADITIONAL,NO_AUTO_VALUE_ON_ZERO,ONLY_FULL_GROUP_BY'|,
            )
            mysql.query_options.update(symbolize_keys: true)
            mysql
          end
      end

      def redis(use_init = true)
        unless Thread.current[:redis]
          Thread.current[:redis] = Redis.new(:host => "127.0.0.1", :db => 0)
          init_keywords if use_init
        end
        Thread.current[:redis]
      end

      def init_keywords
        redis(false).zremrangebyrank('keywords', 0, -1)
        incr.set('update', 0) unless incr.get('update')
        Thread.current[:aho_update] ||= incr.get('update')
        keywords = db.xquery(%| select keyword from entry |)
        keywords.each do |k|
          add_keyword(k[:keyword])
        end
      end

      def add_keyword(keyword)
        redis.zadd 'keywords', keyword.length, keyword
        redis.incr('update')
      end

      def del_keyword(keyword)
        redis.zrem 'keywords', keyword
        redis.incr('update')
      end

      def get_keywords
        redis.zrevrange('keywords', 0, -1)
      end

      def aho_corasick
        update = redis.get('update')
        if update > Thread.current[:aho_update]
          Thread.current[:aho] = nil
          Thread.current[:aho_update] = update
        end
        Thread.current[:aho] ||= AhoCorasickMatcher.new(get_keywords())
      end

      def register(name, pw) # nameとpwを
        chars = [*'A'..'~']
        salt = 1.upto(20).map { chars.sample }.join('')
        salted_password = encode_with_salt(password: pw, salt: salt)
        db.xquery(%|
          INSERT INTO user (name, salt, password, created_at)
          VALUES (?, ?, ?, NOW())
        |, name, salt, salted_password)
        db.last_id
      end

      def encode_with_salt(password: , salt: ) # ソルト作る
        Digest::SHA1.hexdigest(salt + password)
      end

      def is_spam_content(content) # 謎のisupamは、スパムチェッカ。
        isupam_uri = URI(settings.isupam_origin)
        res = Net::HTTP.post_form(isupam_uri, 'content' => content)
        validation = JSON.parse(res.body)
        validation['valid']
        ! validation['valid']
      end

      def htmlify(content)
        # pattern = get_keywords.join('|')
        # kw2hash = {} # kw2hash
        # hashed_content = content.gsub(/(#{pattern})/) {|m| # キーワードをハッシュに置換する
        #   matched_keyword = $1
        #   "isuda_#{Digest::SHA1.hexdigest(matched_keyword)}".tap do |hash|
        #     kw2hash[matched_keyword] = hash
        #   end
        # }
        # escaped_content = Rack::Utils.escape_html(hashed_content) #
        # kw2hash.each do |(keyword, hash)| # ハッシュをアンカーに置換する
        #   keyword_url = url("/keyword/#{Rack::Utils.escape_path(keyword)}")
        #   anchor = '<a href="%s">%s</a>' % [keyword_url, Rack::Utils.escape_html(keyword)] # 作ってどっかに予め放り込んでおくのアリ
        #   escaped_content.gsub!(hash, anchor)
        # end
        # escaped_content.gsub(/\n/, "<br />\n")
        escaped_content = aho_corasick.create_autolink(content)
        escaped_content.gsub(/\n/, "<br />\n")
      end

      def uri_escape(str)
        Rack::Utils.escape_path(str)
      end

      def load_stars(keyword) # TODO タイムアウト キーワードに一致するスターを取ってくる、isutarの実装を持ってくるか、DB叩くのが早そう
        # isutar_url = URI(settings.isutar_origin)
        # isutar_url.path = '/stars'
        # isutar_url.query = URI.encode_www_form(keyword: keyword)
        # body = Net::HTTP.get(isutar_url)
        keyword = keyword || ''
        db.xquery(%| select * from star where keyword = ? |, keyword).to_a
        # stars_res = JSON.parse(body)
        # stars_res['stars']
      end

      def redirect_found(path)
        redirect(path, 302)
      end
    end

    get '/initialize' do
      db.xquery(%| DELETE FROM entry WHERE id > 7101 |)
      db.xquery('TRUNCATE star')
      # isutar_initialize_url = URI(settings.isutar_origin)
      # isutar_initialize_url.path = '/initialize'
      # Net::HTTP.get_response(isutar_initialize_url)

      init_keywords

      content_type :json
      JSON.generate(result: 'ok')
    end

    get '/', set_name: true do
      per_page = 10
      page = (params[:page] || 1).to_i

      entries = db.xquery(%|
        SELECT * FROM entry
        ORDER BY updated_at DESC
        LIMIT #{per_page}
        OFFSET #{per_page * (page - 1)}
      |)
      entries.each do |entry| # ここ重そう
        entry[:html] = htmlify(entry[:description])
        entry[:stars] = load_stars(entry[:keyword])
      end

      total_entries = db.xquery(%| SELECT count(*) AS total_entries FROM entry |).first[:total_entries].to_i # エントリの全数を取得

      last_page = (total_entries.to_f / per_page.to_f).ceil # ここからペジネーション処理
      from = [1, page - 5].max
      to = [last_page, page + 5].min
      pages = [*from..to]

      locals = {
        entries: entries, # エントリ一覧
        page: page, # ページ番号
        pages: pages, # ページ番号の配列
        last_page: last_page, # 最後のページ番号
      }
      erb :index, locals: locals
    end

    get '/robots.txt' do
      halt(404)
    end

    get '/register', set_name: true do
      erb :register
    end

    post '/register' do
      name = params[:name] || ''
      pw   = params[:password] || ''
      halt(400) if (name == '') || (pw == '')

      user_id = register(name, pw)
      session[:user_id] = user_id

      redirect_found '/'
    end

    get '/login', set_name: true do # もしかしたら無駄？
      locals = {
        action: 'login',
      }
      erb :authenticate, locals: locals
    end

    post '/login' do # TODO タイムアウト
      name = params[:name]
      user = db.xquery(%| select id,password,salt from user where name = ? |, name).first
      halt(403) unless user
      halt(403) unless user[:password] == encode_with_salt(password: params[:password], salt: user[:salt])

      session[:user_id] = user[:id]

      redirect_found '/'
    end

    get '/logout' do
      session[:user_id] = nil
      redirect_found '/'
    end

    post '/keyword', set_name: true, authenticate: true do # ここ重要そう（TODO タイムアウト
      keyword = params[:keyword] || ''
      halt(400) if keyword == '' # はてなキーワード
      description = params[:description]
      halt(400) if is_spam_content(description) || is_spam_content(keyword) # ここ重そう

      bound = [@user_id, keyword, description] * 2
      db.xquery(%|
        INSERT INTO entry (author_id, keyword, description, created_at, updated_at)
        VALUES (?, ?, ?, NOW(), NOW())
        ON DUPLICATE KEY UPDATE
        author_id = ?, keyword = ?, description = ?, updated_at = NOW()
      |, *bound) # キーワード同一になってたら、description更新？

      add_keyword(keyword)

      redirect_found '/'
    end

    get '/keyword/:keyword', set_name: true do
      keyword = params[:keyword] or halt(400)

      entry = db.xquery(%| select * from entry where keyword = ? |, keyword).first or halt(404)
      entry[:stars] = load_stars(entry[:keyword]) # 重そう
      entry[:html] = htmlify(entry[:description]) # 参照のたびにするの無駄、更新時にやって

      locals = {
        entry: entry,
      }
      erb :keyword, locals: locals
    end

    post '/keyword/:keyword', set_name: true, authenticate: true do
      keyword = params[:keyword] or halt(400)
      is_delete = params[:delete] or halt(400)

      unless db.xquery(%| SELECT * FROM entry WHERE keyword = ? |, keyword).first
        halt(404)
      end

      db.xquery(%| DELETE FROM entry WHERE keyword = ? |, keyword) # うまいこと246と結合できないか
      del_keyword(keyword)

      redirect_found '/'
    end

    post '/stars' do
      keyword = params[:keyword]

      # isuda_keyword_url = URI(settings.isuda_origin)
      # isuda_keyword_url.path = '/keyword/%s' % [Rack::Utils.escape_path(keyword)]
      # res = Net::HTTP.get_response(isuda_keyword_url)
      # halt(404) unless Net::HTTPSuccess === res
      unless db.xquery(%| SELECT * FROM entry WHERE keyword = ? |, keyword).first
        halt(404)
      end

      user_name = params[:user]
      db.xquery(%|
        INSERT INTO star (keyword, user_name, created_at)
        VALUES (?, ?, NOW())
      |, keyword, user_name)

      content_type :json
      JSON.generate(result: 'ok')
    end
  end
end
