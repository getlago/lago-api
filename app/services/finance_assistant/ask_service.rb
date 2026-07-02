# frozen_string_literal: true

module FinanceAssistant
  class AskService < BaseService
    Result = BaseResult[:answer]

    # Keys the GraphQL FinanceAssistantAnswer type exposes as non-nullable
    REQUIRED_ANSWER_KEYS = %w[explanation results session_id session_expired message_id].freeze

    def initialize(organization:, question:, session_id: nil)
      @organization = organization
      @question = question
      @session_id = session_id

      super()
    end

    def call
      return result.forbidden_failure! if finance_assistant_url.blank?

      response = http_client.post_with_response(request_body, headers)
      body = JSON.parse(response.body.presence || "{}")

      unless valid_answer?(body)
        return result.service_failure!(
          code: "finance_assistant_invalid_response",
          message: "Malformed response from the finance assistant"
        )
      end

      result.answer = body
      result
    rescue LagoHttpClient::HttpError => e
      result.service_failure!(
        code: "finance_assistant_error",
        message: e.json_message["detail"].presence || e.message,
        error: e
      )
    rescue JSON::ParserError => e
      result.service_failure!(code: "finance_assistant_invalid_response", message: e.message, error: e)
    rescue => e
      result.service_failure!(code: "finance_assistant_error", message: e.message, error: e)
    end

    private

    attr_reader :organization, :question, :session_id

    def valid_answer?(body)
      body.is_a?(Hash) && REQUIRED_ANSWER_KEYS.all? { |key| !body[key].nil? }
    end

    def request_body
      payload = {question:}
      payload[:session_id] = session_id if session_id.present?
      payload
    end

    def headers
      {
        "X-LAGO-API-KEY" => organization.api_keys.with_most_permissions.value,
        "X-Organization-Id" => organization.id
      }
    end

    def http_client
      LagoHttpClient::Client.new(
        "#{finance_assistant_url.chomp("/")}/ask",
        open_timeout: 5,
        read_timeout: 60
      )
    end

    def finance_assistant_url
      ENV["LAGO_FINANCE_ASSISTANT_URL"]
    end
  end
end
