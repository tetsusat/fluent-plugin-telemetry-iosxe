require "helper"

class TelemetryIosxeInputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup  # this is required to setup router and others
  end

  # default configuration for tests
  CONFIG = %[
    server 127.0.0.1
    port 830
    xpath_filter /ios-emul-oper-db:ios-emul-oper-db/cpu-usage/five-seconds
    period 500
    tag cpu-usage-five-seconds
  ]

  def create_driver(conf = CONFIG)
    Fluent::Test::Driver::Input.new(Fluent::TelemetryIosxeInput).configure(conf)
  end

  sub_test_case "configuration" do
    test "configuration" do
      d = create_driver
      assert_equal "127.0.0.1", d.instance.server
      assert_equal 830, d.instance.port
      assert_equal "admin", d.instance.user
      assert_equal "admin", d.instance.password
      assert_equal :nokogiri, d.instance.parser
      assert_equal "/ios-emul-oper-db:ios-emul-oper-db/cpu-usage/five-seconds", d.instance.xpath_filter
      assert_equal 500, d.instance.period
      assert_equal true, d.instance.strip_namespaces
      assert_equal true, d.instance.typecast_integer
      assert_equal "cpu-usage-five-seconds", d.instance.tag
    end
  end
end
