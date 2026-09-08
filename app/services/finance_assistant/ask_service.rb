# frozen_string_literal: true

module FinanceAssistant
  class AskService < BaseService
    Result = BaseResult[:answer]

    # Keys the GraphQL FinanceAssistantAnswer type exposes as non-nullable
    REQUIRED_ANSWER_KEYS = %w[explanation results session_id session_expired message_id].freeze

    # The read timeout must stay above the assistant's own run deadline
    # (ASK_DEADLINE_SECS on its side). Past that deadline it answers with a
    # graceful explanation, and hanging up first turns that answer into a
    # transport error.
    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_READ_TIMEOUT = 60

    def initialize(organization:, question:, session_id: nil)
      @organization = organization
      @question = question
      @session_id = session_id

      super()
    end

    def call
      started_at = monotonic_now

      return result.forbidden_failure! if finance_assistant_url.blank?
      return result.single_validation_failure!(error_code: "value_is_mandatory", field: :question) if question.blank?

      response = http_client.post_with_response(request_body, headers)
      body = JSON.parse(response.body.presence || "{}")

      unless valid_answer?(body)
        log_failure(code: "finance_assistant_invalid_response", started_at:)

        return result.service_failure!(
          code: "finance_assistant_invalid_response",
          message: "Malformed response from the finance assistant"
        )
      end

      result.answer = body
      result
    rescue LagoHttpClient::HttpError => e
      log_failure(code: "finance_assistant_error", started_at:, error: e)

      result.service_failure!(
        code: "finance_assistant_error",
        message: e.json_message["detail"].presence || e.message,
        error: e
      )
    rescue JSON::ParserError => e
      log_failure(code: "finance_assistant_invalid_response", started_at:, error: e)

      result.service_failure!(code: "finance_assistant_invalid_response", message: e.message, error: e)
    rescue => e
      log_failure(code: "finance_assistant_error", started_at:, error: e)

      result.service_failure!(code: "finance_assistant_error", message: e.message, error: e)
    end

    private

    attr_reader :organization, :question, :session_id

    def valid_answer?(body)
      body.is_a?(Hash) && REQUIRED_ANSWER_KEYS.all? { |key| !body[key].nil? }
    end

    # Every failure reaches the caller as the same generic GraphQL error, so the
    # duration is the only way to tell a timeout after a minute of work from an
    # immediate refusal.
    def log_failure(code:, started_at:, error: nil)
      context = {
        organization_id: organization.id,
        code:,
        duration: (monotonic_now - started_at).round(2),
        error: error&.class&.name,
        error_message: error&.message&.inspect
      }

      Rails.logger.warn("FinanceAssistant::AskService failed #{context.map { |k, v| "#{k}=#{v}" }.join(" ")}")
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def request_body
      payload = {question:}
      payload[:session_id] = session_id if session_id.present?
      payload
    end

    def headers
      {"X-LAGO-API-KEY" => organization.api_keys.with_most_permissions.value}
    end

    def http_client
      LagoHttpClient::Client.new(
        "#{finance_assistant_url.chomp("/")}/ask",
        open_timeout: timeout_from_env("LAGO_FINANCE_ASSISTANT_OPEN_TIMEOUT", DEFAULT_OPEN_TIMEOUT),
        read_timeout: timeout_from_env("LAGO_FINANCE_ASSISTANT_READ_TIMEOUT", DEFAULT_READ_TIMEOUT)
      )
    end

    # Net::HTTP reads a zero timeout as "give up immediately", so anything that is
    # not a positive number of seconds falls back to the default.
    def timeout_from_env(name, default)
      seconds = ENV[name].to_i

      seconds.positive? ? seconds : default
    end

    def finance_assistant_url
      ENV["LAGO_FINANCE_ASSISTANT_URL"]
    end
  end
end
