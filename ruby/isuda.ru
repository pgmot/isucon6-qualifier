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
  require "mysql2/client/general_log"
end

run Isuda::Web
