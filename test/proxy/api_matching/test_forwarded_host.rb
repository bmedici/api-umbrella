require_relative "../../test_helper"

class Test::Proxy::ApiMatching::TestForwardedHost < Minitest::Test
  include ApiUmbrellaTestHelpers::Setup
  include ApiUmbrellaTestHelpers::ApiMatching

  def setup
    setup_server
    once_per_class_setup do
      prepend_api_backends([
        {
          :frontend_host => "#{unique_test_class_id}-a",
          :backend_host => "127.0.0.1",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/", :backend_prefix => "/" }],
          :settings => {
            :headers => [
              { :key => "X-Backend", :value => "host-a" },
            ],
          },
        },
        {
          :frontend_host => "#{unique_test_class_id}-b",
          :backend_host => "127.0.0.1",
          :servers => [{ :host => "127.0.0.1", :port => 9444 }],
          :url_matches => [{ :frontend_prefix => "/", :backend_prefix => "/" }],
          :settings => {
            :headers => [
              { :key => "X-Backend", :value => "host-b" },
            ],
          },
        },
      ])
    end
  end

  def test_ignores_forwarded_host_by_default
    response = make_request_to_host("#{unique_test_class_id}-a", "/info/", :headers => { "X-Forwarded-Host" => "#{unique_test_class_id}-b" })
    assert_backend_match("host-a", response)
  end

  def test_uses_forwarded_host_when_enabled
    override_config({
      :router => {
        :match_x_forwarded_host => true,
      },
    }, "--router") do
      response = make_request_to_host("#{unique_test_class_id}-a", "/info/", :headers => { "X-Forwarded-Host" => "#{unique_test_class_id}-b" })
      assert_backend_match("host-b", response)
    end
  end
end
