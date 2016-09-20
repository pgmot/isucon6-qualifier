#!rackup

require 'dotenv'
Dotenv.load

require_relative './lib/isuda/web.rb'

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
  module SqlLog
    class Log < Struct.new(:sql, :backtrace, :time); end

    class Logger < Array
      def format_log(log, opt = {})
        time = sprintf('%07.2f', log.time)
        sql = log.sql.gsub(/[\r\n]/, ' ').gsub(/ +/, ' ').strip
        backtrace = if log.backtrace[0].to_s.include?(%(in `xquery'))
                      log.backtrace[1]
                    else
                      log.backtrace[0]
                    end

        "SQL\t(#{time}ms)\t`#{sql}`".tap do |text|
          text << "\t#{backtrace}" if opt[:backtrace]
        end
      end

      def save(option = {})
        opt = { path: '/tmp/sql.log', backtrace: false }.merge(option)
        req = opt[:req]
        File.open(opt[:path], 'a') do |file|
          if req
            file.puts "REQUEST\t#{req.request_method}\t#{req.path}\t#{self.length}"
          end

          self.each do |log|
            file.puts format_log(log, opt)
          end
          file.puts ''
        end
        self.clear
      end
    end

    attr_accessor :general_log

    def initialize(opts = {})
      @general_log = Logger.new
      super opts
    end

    def query(sql, options = {})
      start_time = Time.now
      ret = super(sql, options)
      time = (Time.now - start_time) * 1000
      @general_log << Log.new(sql, caller_locations, time)
      ret
    end
  end
  Mysql2::Client.send(:prepend, SqlLog)
end

run Isuda::Web
