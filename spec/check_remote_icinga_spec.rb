require 'spec_helper'
require 'stringio'

module Icinga
  describe CheckIcinga do
    let(:stdout)   { StringIO.new }
    let(:stderr)   { StringIO.new }

    describe "#run" do
      let(:stdopts) { {:stdout => stdout, :stderr => stderr } }
      it "Will print a help message" do
        args = [ "--help" ]
        Icinga::CheckIcinga.new(args, stdopts).run

        stdout.string.should match(/check icinga/i)
        stdout.string.should match(/--url/i)
      end

      it "Will fail, when neither check_services nor check_hosts mode is active" do
        args = [ ]
        Icinga::CheckIcinga.new(args, stdopts).run.should eq(Icinga::EXIT_UNKNOWN)

        stderr.string.should match(/choose either hosts or services mode/i)
      end
    end

    describe "#check" do
      let(:stdopts) { {:stdout => stdout, :stderr => stderr, :excon => {:mock => true} } }
      before(:each) do
        Excon.stubs.clear
      end
      describe "#check_hosts" do

        it "Will return ok, when all hosts are good" do
          resp = {
            "cgi_json_version"=>"1.5.0",
            "status"=>
            {"host_status"=> [{"host"=>"host1",
                                "status"=>"UP",
                                "last_check"=>"01-25-2012 17:15:22",
                                "duration"=>"9d  8h 18m 50s",
                                "attempts"=>"1/3",
                                "status_information"=> "HTTP OK"},
                              {"host"=>"host2",
                                "status"=>"UP",
                                "last_check"=>"01-25-2012 17:15:32",
                                "duration"=>"9d  7h 58m  4s",
                                "attempts"=>"1/3",
                                "status_information"=>"PING OK - Packet loss = 0%, RTA = 0.44 ms"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "hosts", "--min", "2" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run

          rc.should == Icinga::EXIT_OK
          stdout.string.should match(/ok: 2=ok, 0=fail/i)
        end

        it "Will return warning, when warning limit is reached" do
          resp = {
            "cgi_json_version"=>"1.5.0",
            "status"=>
            {"host_status"=> [{"host"=>"host1",
                                "status"=>"DOWN",
                                "last_check"=>"01-25-2012 17:15:22",
                                "duration"=>"9d  8h 18m 50s",
                                "attempts"=>"3/3",
                                "status_information"=> "HTTP OK"},
                              {"host"=>"host2",
                                "status"=>"UP",
                                "last_check"=>"01-25-2012 17:15:32",
                                "duration"=>"9d  7h 58m  4s",
                                "attempts"=>"1/3",
                                "status_information"=>"PING OK - Packet loss = 0%, RTA = 0.44 ms"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "hosts", "--warn", "1", "--crit", "2", "--min", "2" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_WARN
          stdout.string.should match(/warn: 1 hosts fail/i)
        end

        it "Will return warning, when warning limit is reached (soft state enabled)" do
          resp = {
            "cgi_json_version"=>"1.5.0",
            "status"=>
            {"host_status"=> [{"host"=>"host1",
                                "status"=>"DOWN",
                                "last_check"=>"01-25-2012 17:15:22",
                                "duration"=>"9d  8h 18m 50s",
                                "attempts"=>"2/3",
                                "status_information"=> "HTTP OK"},
                              {"host"=>"host2",
                                "status"=>"UP",
                                "last_check"=>"01-25-2012 17:15:32",
                                "duration"=>"9d  7h 58m  4s",
                                "attempts"=>"1/3",
                                "status_information"=>"PING OK - Packet loss = 0%, RTA = 0.44 ms"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "hosts", "--warn", "1", "--crit", "2", "--min", "2", "--trigger-soft-state" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_WARN
          stdout.string.should match(/warn: 1 hosts fail/i)
        end

        it "Will return critial, when critical limit is reached" do
          resp = {
            "cgi_json_version"=>"1.5.0",
            "status"=>
            {"host_status"=> [{"host"=>"host1",
                                "status"=>"DOWN",
                                "last_check"=>"01-25-2012 17:15:22",
                                "duration"=>"9d  8h 18m 50s",
                                "attempts"=>"3/3",
                                "status_information"=> "HTTP OK"},
                              {"host"=>"host2",
                                "status"=>"DOWN",
                                "last_check"=>"01-25-2012 17:15:32",
                                "duration"=>"9d  7h 58m  4s",
                                "attempts"=>"3/3",
                                "status_information"=>"PING OK - Packet loss = 0%, RTA = 0.44 ms"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "hosts", "--warn", "1", "--crit", "2", "--min", "2" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_CRIT
          stdout.string.should match(/crit: 2 hosts fail/i)
        end

        it "Will return critical, when less than expected hosts are found" do
          resp = {
            "cgi_json_version"=>"1.5.0",
            "status"=>
            {"host_status"=> [{"host"=>"host1",
                                "status"=>"UP",
                                "last_check"=>"01-25-2012 17:15:22",
                                "duration"=>"9d  8h 18m 50s",
                                "attempts"=>"1/3",
                                "status_information"=> "HTTP OK"},
                              {"host"=>"host2",
                                "status"=>"UP",
                                "last_check"=>"01-25-2012 17:15:32",
                                "duration"=>"9d  7h 58m  4s",
                                "attempts"=>"1/3",
                                "status_information"=>"PING OK - Packet loss = 0%, RTA = 0.44 ms"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "hosts", "--warn", "1", "--crit", "2", "--min", "5" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          stdout.string.should match(/crit: only 2 hosts/i)
          rc.should == Icinga::EXIT_CRIT
        end

        it "Will return critical, when timeout is met" do
          Excon.stub({:method => :get}) do |_|
            sleep 2
          end

          args = [ "--mode", "hosts", "--warn", "1", "--crit", "2", "--min", "2", "--timeout", "1" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_CRIT
          stdout.string.should match(/Timeout after/i)
        end

        it "Will return ok, when all non-good hosts are excluded" do
          resp = {
            "cgi_json_version"=>"1.5.0",
            "status"=>
            {"host_status"=> [{"host"=>"unstable backend",
                                "status"=>"DOWN",
                                "last_check"=>"01-25-2012 17:15:22",
                                "duration"=>"9d  8h 18m 50s",
                                "attempts"=>"1/3",
                                "status_information"=> "HTTP OK"},
                              {"host"=>"host2",
                                "status"=>"UP",
                                "last_check"=>"01-25-2012 17:15:32",
                                "duration"=>"9d  7h 58m  4s",
                                "attempts"=>"1/3",
                                "status_information"=>"PING OK - Packet loss = 0%, RTA = 0.44 ms"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "hosts", "--min", "1", "--exclude", "unstable"]
          rc = Icinga::CheckIcinga.new(args, stdopts).run

          rc.should == Icinga::EXIT_OK
          stdout.string.should match(/ok: 1=ok, 0=fail, 1=other/i)
        end
      end

      describe "#check_services" do
        it "Will return ok, when all services are good" do
          resp = {
            "cgi_json_version" => "1.5.0",
            "status" => { "service_status" => [{ "host" => "hostA",
                                                 "service" => "HTTP",
                                                 "status" => "OK",
                                                 "last_check" => "01-25-2012 18:05:30",
                                                 "duration" => "15d 19h 55m  1s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "HTTP OK"},
                                               { "host" => "hostB",
                                                 "service" => "ActiveMQ MemoryPercentUsage",
                                                 "status" => "OK",
                                                 "last_check" => "01-25-2012 18:05:25",
                                                 "duration" => "13d  6h 30m 42s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "JMX OK PercentUsage=0"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "services", "--warn", "1", "--crit", "2", "--min", "2" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_OK
          stdout.string.should match(/ok: 2=ok, 0=fail/i)
        end

        it "Will return warning, when warning limit is reached" do
          resp = {
            "cgi_json_version" => "1.5.0",
            "status" => { "service_status" => [{ "host" => "hostA",
                                                 "service" => "HTTP",
                                                 "status" => "WARNING",
                                                 "last_check" => "01-25-2012 18:05:30",
                                                 "duration" => "15d 19h 55m  1s",
                                                 "attempts" => "5/5",
                                                 "status_information" => "HTTP OK"},
                                               { "host" => "hostB",
                                                 "service" => "ActiveMQ MemoryPercentUsage",
                                                 "status" => "OK",
                                                 "last_check" => "01-25-2012 18:05:25",
                                                 "duration" => "13d  6h 30m 42s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "JMX OK PercentUsage=0"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "services", "--warn", "1", "--crit", "2", "--min", "2" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_WARN
          stdout.string.should match(/warn: 1 services fail/i)
        end

        it "Will return critial, when critical limit is reached" do
          resp = {
            "cgi_json_version" => "1.5.0",
            "status" => { "service_status" => [{ "host" => "hostA",
                                                 "service" => "HTTP",
                                                 "status" => "WARNING",
                                                 "last_check" => "01-25-2012 18:05:30",
                                                 "duration" => "15d 19h 55m  1s",
                                                 "attempts" => "5/5",
                                                 "status_information" => "HTTP OK"},
                                               { "host" => "hostB",
                                                 "service" => "ActiveMQ MemoryPercentUsage",
                                                 "status" => "CRITICAL",
                                                 "last_check" => "01-25-2012 18:05:25",
                                                 "duration" => "13d  6h 30m 42s",
                                                 "attempts" => "5/5",
                                                 "status_information" => "JMX OK PercentUsage=0"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "services", "--warn", "1", "--crit", "2", "--min", "2" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_CRIT
          stdout.string.should match(/crit: 2 services fail/i)
        end

        it "Will return critical, when less than expected services are found" do
          resp = {
            "cgi_json_version" => "1.5.0",
            "status" => { "service_status" => [{ "host" => "hostA",
                                                 "service" => "HTTP",
                                                 "status" => "WARNING",
                                                 "last_check" => "01-25-2012 18:05:30",
                                                 "duration" => "15d 19h 55m  1s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "HTTP OK"},
                                               { "host" => "hostB",
                                                 "service" => "ActiveMQ MemoryPercentUsage",
                                                 "status" => "OK",
                                                 "last_check" => "01-25-2012 18:05:25",
                                                 "duration" => "13d  6h 30m 42s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "JMX OK PercentUsage=0"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "services", "--warn", "1", "--crit", "2", "--min", "3" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_CRIT
          stdout.string.should match(/crit: only 2 services found/i)
        end

        it "Will return critical, when timeout is met" do
          Excon.stub({:method => :get}) do |_|
            sleep 2
          end

          args = [ "--mode", "services", "--warn", "1", "--crit", "2", "--min", "2", "--timeout", "1" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_CRIT
          stdout.string.should match(/Timeout after/i)
        end

        it "Will return OK. Count ack'ed, disabled notifications and scheduled downtimes as 'other'" do
          resp = {
            "cgi_json_version" => "1.7.1",
            "status" => { "service_status" => [{ "passive_checks_enabled"=>true,
                                                 "notifications_enabled"=>true,
                                                 "is_flapping"=>false,
                                                 "in_scheduled_downtime"=>true,
                                                 "attempts"=>"1/3",
                                                 "has_been_acknowledged"=>false,
                                                 "service"=>"Solr FOO - non empty search",
                                                 "status_information"=> "HTTP OK: HTTP/1.1 200 OK - 13595 bytes in 0.012 second response time",
                                                 "service_display_name"=>"Solr FOO - non empty search",
                                                 "active_checks_enabled"=>true,
                                                 "host"=>"search.example.com",
                                                 "duration"=>"9d 15h 19m 44s",
                                                 "status"=>"WARNING",
                                                 "host_display_name"=>"search.example.com",
                                                 "last_check"=>"2012-09-14 14:58:54" },
                                               { "passive_checks_enabled"=>true,
                                                 "notifications_enabled"=>true,
                                                 "is_flapping"=>false,
                                                 "in_scheduled_downtime"=>false,
                                                 "attempts"=>"1/3",
                                                 "has_been_acknowledged"=>true,
                                                 "service"=>"Solr rollingrock - non empty search",
                                                 "status_information"=>"HTTP OK: HTTP/1.1 200 OK - 26075 bytes in 0.012 second response time",
                                                 "service_display_name"=>"Solr BAR - non empty search",
                                                 "active_checks_enabled"=>true,
                                                 "host"=>"search.example.com",
                                                 "duration"=>"9d 15h 19m 12s",
                                                 "status"=>"WARNING",
                                                 "host_display_name"=>"search.example.com",
                                                 "last_check"=>"2012-09-14 14:58:46" },
                                               { "passive_checks_enabled"=>true,
                                                 "notifications_enabled"=>false,
                                                 "is_flapping"=>false,
                                                 "in_scheduled_downtime"=>false,
                                                 "attempts"=>"1/3",
                                                 "has_been_acknowledged"=>false,
                                                 "service"=>"Solr rollingrock - non empty search",
                                                 "status_information"=>"HTTP OK: HTTP/1.1 200 OK - 26075 bytes in 0.012 second response time",
                                                 "service_display_name"=>"Solr BAR - non empty search",
                                                 "active_checks_enabled"=>true,
                                                 "host"=>"search.example.com",
                                                 "duration"=>"9d 15h 19m 12s",
                                                 "status"=>"WARNING",
                                                 "host_display_name"=>"search.example.com",
                                                 "last_check"=>"2012-09-14 14:58:46" },
                                               { "host" => "hostB",
                                                 "service" => "ActiveMQ MemoryPercentUsage",
                                                 "status" => "OK",
                                                 "last_check" => "01-25-2012 18:05:25",
                                                 "duration" => "13d  6h 30m 42s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "JMX OK PercentUsage=0"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "services", "--warn", "1", "--crit", "1" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_OK
          stdout.string.should match(/ok: 1=ok, 0=fail, 3=other/i)
        end

        it "Will return ok, when non-good services are excluded" do
          resp = {
            "cgi_json_version" => "1.5.0",
            "status" => { "service_status" => [{ "host" => "hostA",
                                                 "service" => "HTTP",
                                                 "status" => "WARNING",
                                                 "last_check" => "01-25-2012 18:05:30",
                                                 "duration" => "15d 19h 55m  1s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "HTTP OK"},
                                               { "host" => "hostB",
                                                 "service" => "ActiveMQ MemoryPercentUsage",
                                                 "status" => "OK",
                                                 "last_check" => "01-25-2012 18:05:25",
                                                 "duration" => "13d  6h 30m 42s",
                                                 "attempts" => "1/5",
                                                 "status_information" => "JMX OK PercentUsage=0"}]}}
          Excon.stub({:method => :get}, {:body => resp.to_json, :status => 200})

          args = [ "--mode", "services", "--warn", "1", "--crit", "2", "--min", "1", "--exclude", "HTTP" ]
          rc = Icinga::CheckIcinga.new(args, stdopts).run
          rc.should == Icinga::EXIT_OK
          stdout.string.should match(/ok: 1=ok, 0=fail, 1=other/i)
        end

      end
    end
  end
end
