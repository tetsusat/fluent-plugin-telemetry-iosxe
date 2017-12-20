require "fluent/input"
require "time"
require "net/ssh"
require "nori"

class String
  def is_i?
    self.to_i.to_s == self
  end

  def is_f?
    self.to_f.to_s == self
  end
end

module Fluent
  class TelemetryIosxeInput < Input
    Fluent::Plugin.register_input("telemetry_iosxe", self)
    config_param :server, :string
    config_param :port, :integer, default: 830
    config_param :user, :string, default: "admin"
    config_param :password, :string, default: "admin", secret: true
    config_param :parser, :enum,list: [:rexml, :nokogiri], default: :nokogiri
    config_param :xpath_filter, :string
    config_param :tag, :string
    config_param :period, :integer
    config_param :strip_namespaces, :bool, default: true
    config_param :typecast_integer, :bool, default: true
    config_param :typecast_float, :bool, default: true

    def configure(conf)
      super
    end

    def start
      super
      @sigint = false
      trap :INT do
        log.info "got SIGINT ..."
        @sigint = true
      end
      @hello_done = false
      @buffer = ""
      @parser = Nori.new(:parser => @parser, :advanced_typecasting => false)
      hello = <<-EOS
<?xml version="1.0" encoding="UTF-8"?>
<hello xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
  <capabilities>
    <capability>urn:ietf:params:netconf:base:1.0</capability>
  </capabilities>
</hello>]]>]]>
      EOS

      subscription = <<-EOS
<?xml version="1.0" encoding="utf-8"?>
<rpc message-id="101" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
  <establish-subscription xmlns="urn:ietf:params:xml:ns:yang:ietf-event-notifications" xmlns:yp="urn:ietf:params:xml:ns:yang:ietf-yang-push">
    <stream>yp:yang-push</stream>
    <yp:xpath-filter>#{@xpath_filter}</yp:xpath-filter>
    <yp:period>#{@period}</yp:period>
  </establish-subscription>
</rpc>
      EOS
      
      @ssh = Net::SSH.start(@server, @user, :port => @port, :password => @password, :timeout => 10)
      @channel = @ssh.open_channel do |channel|
        channel.subsystem("netconf") do |ch, success|
          raise "subsystem could not be started" unless success
          ch.on_data do |c, data|
            log.debug "on data ..."
            log.debug data
            receive_data(data)
          end
          ch.on_close do |c|
            log.debug "on close ..."
          end
          ch.on_eof do |c|
            log.debug "on eof ..."
          end
          log.info "send hello"
          ch.send_data(hello)
          log.info "send subscription"
          ch.send_data(subscription)
        end
      end
      @ssh.loop(1) { not @sigint } # if we get sigint, we need to end loop 
    end

    def shutdown
      log.info "shutdown ..."
      delete_subscription = <<-EOS
<?xml version="1.0" encoding="utf-8"?>
<rpc message-id="101" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
  <delete-subscription xmlns="urn:ietf:params:xml:ns:yang:ietf-event-notifications" xmlns:netconf="urn:ietf:params:xml:ns:netconf:base:1.0">
    <subscription-id>#{@subscription_id}</subscription-id>
  </delete-subscription>
</rpc>]]>]]>
      EOS
      close_session = <<-EOS
<?xml version="1.0" encoding="utf-8"?>
<rpc message-id="101" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
  <close-session/>
</rpc>]]>]]>
      EOS
      @channel.send_data(delete_subscription)
      @channel.send_data(close_session)
      @ssh.close
      super
    end

    protected
    def receive_data(data)
      log.info "receive data ..."
      if data.include?("]]>]]>")
        msg = data.split("]]>]]>")
        if msg.empty?  # this could happen when data is exactly "]]>]]>"
          if @hello_done
            parse_msg()
          else
            parse_hello()
            @hello_done = true
          end
        else
          for m in msg
            @buffer << m
            if @hello_done
              parse_msg()
            else
              parse_hello()
              @hello_done = true
            end
          end
        end
      else
        @buffer << data
      end
    end

    def parse_hello
      hello = @parser.parse(@buffer)
      log.debug hello
      @session_id = hello["hello"]["session_id"]
      log.info "Session ID is #{@session_id}"
      @buffer = ""
    end

    def parse_msg
      h = @parser.parse(@buffer)
      log.debug h
      if h["notification"]
        iso8601_time = h["notification"]["eventTime"]
        unix_time = Time.iso8601(iso8601_time).to_i
        content = h["notification"]["push_update"]["datastore_contents_xml"]
        traverse(content) do |node, key, parent|
          if @typecast_integer && node.is_i?
            parent[key] = node.to_i unless parent.nil?
          elsif @typecast_float && node.is_f?
            parent[key] = node.to_f unless parent.nil?
          end
        end
        router.emit(@tag, unix_time, content)
      elsif h["rpc_reply"] && h["rpc_reply"]["subscription_id"]
        @subscription_id = h["rpc_reply"]["subscription_id"]
        log.info "Subscription ID is #{@subscription_id}"
      end
      @buffer = ""
    end

    def traverse(obj, key=nil, parent=nil, &blk)
      case obj
      when Hash
        obj.reject! { |k,v| k == "@xmlns" } if @strip_namespaces
        obj.each { |k,v| traverse(v, k, obj, &blk) }
      when Array
        obj.each_with_index { |v,k| traverse(v, k, obj, &blk) }
      else
        blk.call(obj, key, parent)
      end
    end
  end
end
