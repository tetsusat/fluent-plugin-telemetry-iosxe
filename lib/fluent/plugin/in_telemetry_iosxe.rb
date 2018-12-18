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
    config_param :xpath_filter, :string, default: nil, deprecated: "Use 'xpath_filters' instead"
    config_param :xpath_filters, :array, value_type: :string
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
      @subscription_index = 0
      @subscription_ids = []
      @buffer = ""
      @parser = Nori.new(:parser => @parser, :advanced_typecasting => false)
      hello = <<-EOS
<?xml version="1.0" encoding="UTF-8"?>
<hello xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
  <capabilities>
    <capability>urn:ietf:params:netconf:base:1.0</capability>
  <capability>urn:ietf:params:netconf:base:1.1</capability>
  </capabilities>
</hello>]]>]]>
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
        end
      end
      @ssh.loop(1) { not @sigint } # if we get sigint, we need to end loop
    end

    protected
    def receive_data(data)
      log.debug "receive data ..."
      if @hello_done  # Chunked Framing
        if data.include?('##')
          if data == '##'
            parse()
          else
            data.each_line do |line|
              if not line =~ /^(#\d+|##)/
                @buffer << line
              end
            end
            parse()
          end
        else
          data.each_line do |line|
            if not line =~ /^#\d+/
              @buffer << line
            end
          end
        end
      else    # End-of-Message Framing
        if data.include?(']]>]]>')
          if data == ']]>]]>'
            parse()
          else
            data.each_line do |line|
              if line != ']]>]]>'
                @buffer << line
              end
            end
            parse()
          end
        else
          @buffer << data
        end
      end
    end

    def parse
      log.debug "parse!"
      log.debug @buffer
      d = @parser.parse(@buffer)
      if d['hello']
        handle_hello(d)
        @hello_done = true
        subscribe()
      elsif d['notification']
        handle_notification(d)
      elsif d["rpc_reply"]
        if d["rpc_reply"]["subscription_id"]
          handle_subscription_reply(d)
          if @subscription_index < @xpath_filters.size
            subscribe()
          end
        else
          log.fatal d["rpc_reply"]["subscription_result"]
        end
      else
        log.warn "got other messages"
        log.debug d
      end
      @buffer = ''
    end

    def handle_hello(data)
      log.info "got hello session_id=#{data["hello"]["session_id"]}"
      log.debug data
      @session_id = data["hello"]["session_id"]
    end

    def subscribe
      subscription = <<-EOS
<?xml version="1.0" encoding="utf-8"?>
<rpc message-id="#{@subscription_index+1}" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
  <establish-subscription xmlns="urn:ietf:params:xml:ns:yang:ietf-event-notifications" xmlns:yp="urn:ietf:params:xml:ns:yang:ietf-yang-push">
    <stream>yp:yang-push</stream>
    <yp:xpath-filter>#{@xpath_filters[@subscription_index]}</yp:xpath-filter>
    <yp:period>#{@period}</yp:period>
  </establish-subscription>
</rpc>
      EOS
      log.info "subscribe [#{@subscription_index+1}] #{@xpath_filters[@subscription_index]}"
      log.debug chunk_frame(subscription.chomp)
      @channel.send_data(chunk_frame(subscription.chomp))
      @channel.send_data("\n##\n")
      @subscription_index += 1
    end

    def unsubscribe(id)
      delete_subscription = <<-EOS
<?xml version="1.0" encoding="utf-8"?>
<rpc message-id="101" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
  <delete-subscription xmlns="urn:ietf:params:xml:ns:yang:ietf-event-notifications" xmlns:netconf="urn:ietf:params:xml:ns:netconf:base:1.0">
    <subscription-id>#{id}</subscription-id>
  </delete-subscription>
</rpc>
      EOS
      log.info "unubscribe subscription_id=#{id}"
      log.debug chunk_frame(delete_subscription.chomp)
      @channel.send_data(chunk_frame(delete_subscription.chomp))
      @channel.send_data("\n##\n")
    end

    def shutdown
      log.info "shutdown ..."
      for id in @subscription_ids
        unsubscribe(id)
      end
      close_session = <<-EOS
<?xml version="1.0" encoding="utf-8"?>
<rpc message-id="101" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
  <close-session/>
</rpc>
      EOS
      @channel.send_data(chunk_frame(close_session.chomp))
      @channel.send_data("\n##\n")
      @ssh.close
      super
    end

    def chunk_frame(msg)
      "\n##{msg.length}\n" << msg
    end

    def handle_notification(data)
      log.info "got notification"
      log.debug data
      iso8601_time = data["notification"]["eventTime"]
      unix_time = Time.iso8601(iso8601_time).to_i
      content = data["notification"]["push_update"]["datastore_contents_xml"]
      traverse(content) do |node, key, parent|
        if @typecast_integer && node.is_i?
          parent[key] = node.to_i unless parent.nil?
        elsif @typecast_float && node.is_f?
          parent[key] = node.to_f unless parent.nil?
        end
      end
      router.emit(@tag, unix_time, content)
    end

    def handle_subscription_reply(data)
      log.info "got subscription reply subscription_id=#{data['rpc_reply']['subscription_id']}"
      log.debug data
      @subscription_ids << data["rpc_reply"]["subscription_id"]
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
