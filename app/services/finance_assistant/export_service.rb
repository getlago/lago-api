# frozen_string_literal: true

module FinanceAssistant
  class ExportService < BaseService
    Result = BaseResult[:export]

    # Keys the GraphQL FinanceAssistantExport type exposes as non-nullable
    REQUIRED_EXPORT_KEYS = %w[content filename row_count truncated].freeze

    def initialize(organization:, message_id:)
      @organization = organization
      @message_id = message_id

      super()
    end

    def call
      return result.forbidden_failure! if finance_assistant_url.blank?

      response = http_client.post_with_response(request_body, headers)
      body = JSON.parse(response.body.presence || "{}")

      unless valid_export?(body)
        return result.service_failure!(
          code: "finance_assistant_invalid_response",
          message: "Malformed response from the finance assistant"
        )
      end

      result.export = body
      result
    rescue LagoHttpClient::HttpError => e
      # Surface the agent's typed errors (result aged out of its in-memory store,
      # or the query can't be re-run) so the client can react appropriately.
      detail = e.json_message["detail"].presence
      code = %w[export_expired export_unavailable].include?(detail) ? detail : "finance_assistant_error"
      result.service_failure!(code:, message: detail || e.message, error: e)
    rescue JSON::ParserError => e
      result.service_failure!(code: "finance_assistant_invalid_response", message: e.message, error: e)
    rescue => e
      result.service_failure!(code: "finance_assistant_error", message: e.message, error: e)
    end

    private

    attr_reader :organization, :message_id

    def valid_export?(body)
      body.is_a?(Hash) && REQUIRED_EXPORT_KEYS.all? { |key| !body[key].nil? }
    end

    def request_body
      {message_id:}
    end

    def headers
      {
        "X-LAGO-API-KEY" => organization.api_keys.with_most_permissions.value,
        "X-Organization-Id" => organization.id
      }
    end

    def http_client
      # Export re-runs the full query, so it needs a much longer read timeout than
      # the interactive /ask path.
      LagoHttpClient::Client.new(
        "#{finance_assistant_url.chomp("/")}/export",
        open_timeout: 5,
        read_timeout: 300
      )
    end

    def finance_assistant_url
      ENV["LAGO_FINANCE_ASSISTANT_URL"]
    end
  end
end
