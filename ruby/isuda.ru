#!rackup

require_relative './lib/isuda/web.rb'

require 'dotenv'

Dotenv.load
if ENV['STACKPROF'] == '1'
  require 'stackprof'
  Dir.mkdir('/tmp/stackprof/isuda') unless File.exist?('/tmp/stackprof/isuda')
  use StackProf::Middleware, enabled: true,
      mode: :wall,
      interval: 100,
      save_every: 1,
      path: '/tmp/stackprof/isuda'
end

if ENV['SQLLOG'] == '1'
  require 'benchmark'
  module SqlLog
    def query(sql, options = {})
      start_time = Time.now

      res = super(sql, options)

      time = (Time.now - start_time) * 1000
      puts "SQL (#{sprintf('%06.2f', time)}ms) #{sql.gsub(/[\r\n]/, ' ')}"

      res
    end
  end
  Mysql2::Client.send(:prepend, SqlLog)
end

run Isuda::Web
