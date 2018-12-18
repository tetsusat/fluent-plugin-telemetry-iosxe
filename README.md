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
  xpath_filters /process-cpu-ios-xe-oper:cpu-usage/cpu-utilization/five-seconds
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

The output is as below.

```
2018-12-14 03:30:54.000000000 +0000 cpu-usage-five-seconds: {"cpu_usage":{"cpu_utilization":{"five_seconds":1}}}
2018-12-14 03:30:59.000000000 +0000 cpu-usage-five-seconds: {"cpu_usage":{"cpu_utilization":{"five_seconds":2}}}
2018-12-14 03:31:04.000000000 +0000 cpu-usage-five-seconds: {"cpu_usage":{"cpu_utilization":{"five_seconds":1}}}
...
```

### Configuration Example 2

Collect telemetry input and then output to InfluxDB with flattening input.

```
<source>
  @type telemetry_iosxe
  server 192.0.2.1
  port 830
  xpath_filters /process-cpu-ios-xe-oper:cpu-usage/cpu-utilization/five-seconds
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
The inserted date on InfluxDB is as below.

```
> select * from "cpu-usage-five-seconds" limit 5
name: cpu-usage-five-seconds
time                cpu_usage.cpu_utilization.five_seconds
----                --------------------------------------
1544759262000000000 1
1544759267000000000 2
1544759272000000000 1
1544759277000000000 2
1544759282000000000 1
```

**server**

IP address to subscribe to Telemetry publisher.  

**port**

TCP port number to subscribe to Telemetry publisher.  
(default: 830)

**xpath_filter**

This parameter is deprecated. Use 'xpath_filters' instead.

**xpath_filters**

XPath filters to specify the information element to subscribe to.

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
