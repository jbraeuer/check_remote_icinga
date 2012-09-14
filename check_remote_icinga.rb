#! /usr/bin/ruby

# A Nagios/Icinga plugin to check remote Nagios/Icinga installations.
#
# This can be used in Cloud-Computing setups, where Icinga is part of
# setup. This can also be used in bootstrap-scripts.
#
# Jens Braeuer, github.com/jbraeuer
#

require 'rubygems'
require 'optparse'
require 'excon'
require 'uri'
require 'base64'
require 'json'
require 'pp'
require 'timeout'

module Icinga
  EXIT_OK = 0
  EXIT_WARN = 1
  EXIT_CRIT = 2
  EXIT_UNKNOWN = 3

  module HTTPTools
    def basic_auth(username, password)
      credentials = Base64.encode64("#{username}:#{password}").strip
      return "Basic #{credentials}"
    end

    def validate(resp)
      raise "HTTP 401 - Password wrong?" if resp.status == 401
      raise "Did not get HTTP 200 (but a #{resp.status})." unless resp.status == 200
      return resp
    end

    def parse(resp)
      return JSON.parse(resp.body)
    end
  end
  class CheckIcinga
    include Icinga::HTTPTools

    def initialize(args, opts = {:stdout => $stdout, :stderr => $stderr, :excon => {}})
      @args = args
      @modes = [:hosts, :services]
      @stdout, @stderr = opts.delete(:stdout), opts.delete(:stderr)
      @options = { :mode => nil,
                   :debug => false,
                   :timeout => 10,
                   :min => -1,
                   :warn => 1,
                   :crit => 1,
                   :url => "http://localhost",
                   :status_cgi => "cgi-bin/icinga/status.cgi",
                   :username => nil,
                   :password => nil }.merge(opts)

      @parser = OptionParser.new("Check Icinga - Icinga/Nagios plugin to Icinga") do |opts|
        opts.on("--mode MODE", @modes, "Check mode. Either 'hosts' or 'services'.") do |arg|
          @options[:mode] = arg
        end
        opts.on("--min N", Integer, "Number of hosts/services to expect.") do |arg|
          @options[:min] = arg
        end
        opts.on("--warn N", Integer, "Warning level") do |arg|
          @options[:warn] = arg
        end
        opts.on("--crit N", Integer, "Critical level") do |arg|
          @options[:crit] = arg
        end
        opts.on("--username NAME", "HTTP username") do |arg|
          @options[:username] = arg
        end
        opts.on("--password password", "HTTP password") do |arg|
          @options[:password] = arg
        end
        opts.on("--url URL", "URL (default: #{@options[:url]})") do |arg|
          @options[:url] = arg
        end
        opts.on("--status-cgi PATH", "path status.cgi (default: #{@options[:status_cgi]})") do |arg|
          @options[:status_cgi] = arg
        end
        opts.on("--timeout SECONDS", Integer, "Timeout for HTTP request (default: #{@options[:timeout]})") do |arg|
          @options[:timeout] = arg
        end
        opts.on("-d", "--debug") do
          @options[:debug] = true
        end
        opts.on("-h", "--help") do
          @options[:mode] = :help
        end
      end

      @parser.parse(args)
    end

    def debug(msg)
      puts msg if @options[:debug]
    end

    def run
      case @options[:mode]
      when :help
        @stdout.puts @parser
        return EXIT_OK
      when :hosts
        return check_hosts
      when :services
        return check_services
      else
        @stderr.puts "Choose either hosts or services mode"
        return EXIT_UNKNOWN
      end
    end

    private
    def headers
      unless @options[:username].nil? or @options[:password].nil?
        return { "Authorization" => basic_auth(@options[:username], @options[:password]) }
      end
      return {}
    end

    def check_hosts
      query = { :hostgroup => "all",
                :style => "hostdetail",
                :nostatusheader => nil,
                :jsonoutput => nil }
      uri = URI([@options[:url], @options[:status_cgi]].join("/"))
      params = @options[:excon].merge({ :path => uri.path,
                                        :query => query,
                                        :headers => headers })
      debug "Will fetch: #{uri.scheme}://#{uri.host}"
      debug "With param: #{params.inspect}"

      result = { :timeout => true }
      begin
        resp = Timeout::timeout@options[:timeout] do
          Excon.get("#{uri.scheme}://#{uri.host}", params)
        end

        state = parse(validate(resp))
        result = { :ok => 0, :fail => 0 }
        state["status"]["host_status"].each do |h|
          if h["in_scheduled_downtime"]
            result[:other] += 1
            next
          end
          if h["has_been_acknowledged"]
            result[:other] += 1
            next
          end
          result[:ok]   += 1 if     h["status"] == "UP"
          result[:fail] += 1 unless h["status"] == "UP"
        end
      rescue Timeout::Error => e
      end
      return check_limits(result, "hosts")
    end

    def check_services
      query = { :host => "all",
                :nostatusheader => nil,
                :jsonoutput => nil }
      uri = URI([@options[:url], @options[:status_cgi]].join("/"))
      params = @options[:excon].merge({ :path => uri.path,
                                       :query => query,
                                       :headers => headers })
      debug "Will fetch: #{uri.scheme}://#{uri.host}"
      debug "With param: #{params.inspect}"

      result = { :timeout => true }
      begin
        resp = Timeout::timeout@options[:timeout] do
          Excon.get("#{uri.scheme}://#{uri.host}", params)
        end
        state = parse(validate(resp))
        result = { :ok => 0, :fail => 0, :other => 0 }
        state["status"]["service_status"].each do |h|
          if h["in_scheduled_downtime"]
            result[:other] += 1
            next
          end
          if h["has_been_acknowledged"]
            result[:other] += 1
            next
          end
          result[:ok]    += 1 if     h["status"] == "OK"
          result[:fail]  += 1 unless h["status"] == "OK"
        end
      rescue Timeout::Error => e
      end
      return check_limits(result, "services")
    end

    def check_limits(result, msg)
      if result[:timeout]
        @stdout.puts "CRIT: Timeout after #{@options[:timeout]}"
        return EXIT_CRIT
      end
      if @options[:min] > result[:ok] + result[:fail]
        @stdout.puts "CRIT: Only #{result[:ok] + result[:fail]} #{msg} found."
        return EXIT_CRIT
      end
      if result[:fail] >= @options[:crit]
        @stdout.puts "CRIT: #{result[:fail]} #{msg} fail."
        return EXIT_CRIT
      end
      if result[:fail] >= @options[:warn]
        @stdout.puts "WARN: #{result[:fail]} #{msg} fail."
        return EXIT_WARN
      end
      @stdout.puts "OK: #{result[:ok]}=ok, #{result[:fail]}=fail, #{result[:other]}=other"
      return EXIT_OK
    end
  end
end

if __FILE__ == $0
  begin
    exit Icinga::CheckIcinga.new(ARGV).run
  rescue => e
    warn e.message
    warn e.backtrace.join("\n\t")
    exit Icinga::EXIT_UNKNOWN
  end
end
