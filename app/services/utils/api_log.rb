# frozen_string_literal: true

module Utils
  class ApiLog
    # WaterDrop rejects messages over its `max_payload_size` (1_000_012 bytes by default).
    MAX_PAYLOAD_BYTESIZE = 1_000_000

    def self.produce(*, **, &)
      new(*, **, &).produce
    end

    def self.available?
      ENV["LAGO_CLICKHOUSE_ENABLED"].present? &&
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].present? &&
        ENV["LAGO_KAFKA_API_LOGS_TOPIC"].present?
    end

    def initialize(request, response, organization:, &block)
      @request = request
      @response = response
      @organization = organization
      @request_id = request.request_id.presence || SecureRandom.uuid
      @block = block
    end

    def produce
      return unless self.class.available?

      current_time = Time.current.iso8601[...-1]
      KafkaProducer.produce_async(
        topic: ENV["LAGO_KAFKA_API_LOGS_TOPIC"],
        invalid_message_level: :warning,
        key:,
        payload: serialized_payload(logged_at: current_time, created_at: current_time)
      )
    end

    private

    attr_reader :request, :response, :organization, :request_id, :block

    def key
      "#{organization.id}--#{request_id}"
    end

    # A large request or response (e.g. a plan with many charges) can push the message over the
    # Kafka limit. Instead of dropping the whole log, the response, then the request body, are
    # replaced by a marker. Both are Map(String, Nullable(String)) in ClickHouse.
    def serialized_payload(**timestamps)
      full_payload = payload.merge(timestamps)
      json = full_payload.to_json
      return json if json.bytesize <= MAX_PAYLOAD_BYTESIZE

      marker = {truncated: "true", original_bytesize: json.bytesize.to_s}
      json = full_payload.merge(request_response: marker).to_json
      return json if json.bytesize <= MAX_PAYLOAD_BYTESIZE

      full_payload.merge(request_body: marker, request_response: marker).to_json
    end

    def payload
      {
        request_id:,
        organization_id: organization.id,
        api_key_id: CurrentContext.api_key_id,
        api_version:,
        **request_data,
        **response_data
      }
    end

    def request_data
      {
        client: request.user_agent,
        request_body: request.params.except(:controller, :action, :format),
        request_path: request.path,
        request_origin: request.base_url,
        http_method: request.method_symbol
      }
    end

    def response_data
      {
        request_response: response.body.present? ? JSON.parse(response.body) : nil,
        http_status: response.status
      }
    end

    def api_version
      request.path.match(/\/api\/(?<version>v\d+)\/.*/)[:version]
    end
  end
end
