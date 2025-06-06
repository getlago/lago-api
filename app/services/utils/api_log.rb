# frozen_string_literal: true

module Utils
  class ApiLog
    class << self
      def produce(request, response, organization:, request_id: SecureRandom.uuid)
        produce_with_kafka(
          key: "#{organization.id}--#{request_id}",
          payload: {
            request_id:,
            organization_id: organization.id,
            api_key_id: CurrentContext.api_key_id,
            api_version: detect_api_version(request.path),
            **request_data(request),
            **response_data(response)
          }
        )
      end

      private

      def produce_with_kafka(key:, payload:)
        return if ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"].blank?
        return if ENV["LAGO_KAFKA_API_LOGS_TOPIC"].blank?

        current_time = Time.current.iso8601[...-1]
        Karafka.producer.produce_async(
          topic: ENV["LAGO_KAFKA_API_LOGS_TOPIC"],
          key:,
          payload: {
            **payload,
            logged_at: current_time,
            created_at: current_time
          }.to_json
        )
      end

      def request_data(request)
        {
          client: request.user_agent,
          request_body: request.params.except(:controller, :action, :format),
          request_path: request.path,
          request_origin: request.base_url,
          request_http_method: request.method_symbol
        }
      end

      def response_data(response)
        {
          request_response: JSON.parse(response.body),
          request_http_status: response.status
        }
      end

      def detect_api_version(path)
        path.match(/\/api\/(?<version>v\d+)\/.*/)[:version]
      end
    end
  end
end
