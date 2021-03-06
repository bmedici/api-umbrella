module ApiUmbrellaTestHelpers
  module Logging
    private

    def log_http_options
      http_options.deep_merge({
        :headers => {
          "User-Agent" => unique_test_id.downcase,
          "X-Api-Umbrella-Test-Return-Request-Id" => "true",
        },
      })
    end

    def wait_for_log(response, options = {})
      # We prefer to fetch the log based on the unique request ID. However, for
      # some tests, this isn't part of the response (for example, when testing
      # what happens when the client cancels the request before receiving a
      # response). So in those cases, fall back to looking the log up by the
      # unique user agent that was part of the initial request.
      request_id = response.headers["x-api-umbrella-test-request-id"]
      if(options[:lookup_by_unique_user_agent])
        refute(request_id)
        assert_equal(unique_test_id.downcase, response.request.options[:headers]["User-Agent"])
        query = { :term => { :request_user_agent => unique_test_id.downcase } }
      else
        assert_kind_of(String, request_id)
        assert_equal(20, request_id.length)
        query = { :ids => { :values => [request_id] } }
      end

      begin
        Timeout.timeout(15) do
          loop do
            result = LogItem.gateway.client.search({
              :index => "_all",
              :type => "log",
              :body => {
                :query => query,
              },
            })

            if(result && result["hits"] && result["hits"]["total"] >= 1)
              if(result["hits"]["total"] > 1)
                raise "Found more than 1 log result for query. This should not happen. Query: #{query.inspect} Result: #{result.inspect}"
              end

              return {
                :result => result,
                :hit => result["hits"]["hits"][0],
                :hit_source => result["hits"]["hits"][0]["_source"],
              }
            end

            sleep 0.1
          end
        end
      rescue Timeout::Error
        raise Timeout::Error, "Log not found: #{query.inspect}"
      end
    end

    def assert_logs_base_fields(record, user = nil)
      assert_kind_of(Numeric, record["request_at"])
      assert_match(/\A\d{13}\z/, record["request_at"].to_s)
      assert_kind_of(Array, record["request_hierarchy"])
      assert_operator(record["request_hierarchy"].length, :>=, 1)
      assert_equal("127.0.0.1:9080", record["request_host"])
      assert_match(/\A\d+\.\d+\.\d+\.\d+\z/, record["request_ip"])
      assert_equal("GET", record["request_method"])
      assert_kind_of(String, record["request_path"])
      assert_operator(record["request_path"].length, :>=, 1)
      assert_equal("http", record["request_scheme"])
      assert_kind_of(Numeric, record["request_size"])
      assert_kind_of(String, record["request_url"])
      assert_equal(true, record["request_url"].start_with?("http://127.0.0.1:9080/"), record["request_url"])
      assert_kind_of(Numeric, record["response_size"])
      assert_kind_of(Numeric, record["response_status"])
      assert_kind_of(Numeric, record["response_time"])
      assert_kind_of(Numeric, record["internal_gatekeeper_time"])
      assert_kind_of(Numeric, record["proxy_overhead"])

      if(user)
        assert_equal(user.api_key, record["api_key"])
        assert_equal(user.email, record["user_email"])
        assert_equal(user.id, record["user_id"])
        assert_equal("seed", record["user_registration_source"])
      end
    end

    def assert_logs_backend_fields(record)
      assert_kind_of(Numeric, record["backend_response_time"])
    end

    def refute_logs_backend_fields(record)
      refute(record["backend_response_time"])
    end
  end
end
