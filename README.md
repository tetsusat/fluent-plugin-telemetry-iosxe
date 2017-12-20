# fluent-plugin-telemetry-iosxe

[Fluentd](https://fluentd.org/) input plugin to collect IOS-XE telemetry.

## Requirements

`fluent-plugin-telemetry-iosxe` supports fluentd-0.14.0 or later. 

## Installation

### RubyGems

```
$ gem install fluent-plugin-telemetry-iosxe
```

### Bundler

Add following line to your Gemfile:

```ruby
gem "fluent-plugin-telemetry-iosxe"
```

And then execute:

```
$ bundle
```

## Configuration


### Configuration Example 1

Collect telemetry input and then output to stdout.

```
<source>
  @type telemetry_iosxe
  server 192.0.2.1
  port 830
  user admin
  password admin
  xpath_filter /ios-emul-oper-db:ios-emul-oper-db/cpu-usage/five-seconds
  tag cpu-usage-five-seconds
  period 500
  @label @telemetry
</source>
<label @telemetry>
  <match **>
    @type stdout
  </match>
</label>
```

### Configuration Example 2

Collect telemetry input and then output to InfluxDB with flattening input.

```
<source>
  @type telemetry_iosxe
  server 192.0.2.1
  port 830
  xpath_filter /ios-emul-oper-db:ios-emul-oper-db/cpu-usage/five-seconds
  user admin
  password admin
  tag cpu-usage-five-seconds
  period 500
  @label @telemetry
</source>
<label @telemetry>
  <filter **>
    @type flatten_hash
    separator .
  </filter>
  <match **>
    @type influxdb
    host localhost
    port 8086
    dbname telemetry
    user admin
    password admin
    time_precision s
    auto_tags true
  </match>
</label>
```

**server**

IP address to subscribe to Telemetry publisher.  

**port**

TCP port number to subscribe to Telemetry publisher.  
(default: 830)

**xpath_filter**

XPath filter to specify the information element to subscribe to.

**user**

Username to subscribe to Telemetry publisher.  
(default: admin)

**password**

Password to subscribe to  Telemetry publisher.  
(default: admin)

**parser**

XML parser(REXML or Nokogiri) to parse XML encoded messages.
(default: Nokogiri)

**tag**

Fluentd tag.

**period**

Period in centiseconds (1/100 of a second).

**strip_namespaces**

Strip XML namespaces.  
(default: true)

**typecast_integer**

Typecast string-typed integer value to integer.  
(default: true)

**typecast_float**

Typecast string-typed float value to float.  
(default: true)
