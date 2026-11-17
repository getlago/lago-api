# frozen_string_literal: true

# Stubs the Nango action endpoint that the aggregator integrations (Anrok, Avalara, NetSuite...) call,
# so specs run the real HTTP client and the error handling of Integrations::Aggregator::BaseService.
#
#   stub_nango_action(status: 503, body: "")
#   stub_nango_action({status: 503, body: ""}, anrok_draft_taxes_answer) # 503, then a success
#   stub_nango_action_failing_with(Integrations::Aggregator::TaskExpiredError)
module NangoHelper
  NANGO_ACTION_ENDPOINT = "https://api.nango.dev/action/trigger"

  # A Nango answer for each error of Integrations::Aggregator::BaseService.retryable_errors.
  RETRYABLE_ERROR_ANSWERS = {
    "Integrations::Aggregator::BadGatewayError" => {status: 502, body: "502 Bad Gateway"},
    "Integrations::Aggregator::RequestLimitError" => {status: 429, body: {error: {code: "SSS_REQUEST_LIMIT_EXCEEDED"}}.to_json},
    "Integrations::Aggregator::OutOfMemoryError" => {
      status: 200,
      body: {succeededInvoices: [], failedInvoices: [{validation_errors: "function_runtime_out_of_memory"}]}.to_json
    },
    "Integrations::Aggregator::TaskInProgressError" => {
      status: 500,
      body: {error: {code: "action_script_failure", message: "Task abc12345-1234-1234-1234-abc123456789 is in progress"}}.to_json
    },
    "Integrations::Aggregator::TaskExpiredError" => {
      status: 500,
      body: {error: {code: "action_script_failure", message: "Task abc12345-1234-1234-1234-abc123456789 expired"}}.to_json
    },
    "Integrations::Aggregator::OrchestratorFailureError" => {
      status: 500,
      body: {error: {code: "action_script_failure", message: "POST http://nango-orchestrator-svc.nango/v1/immediate failed"}}.to_json
    },
    "Integrations::Aggregator::ServerContentionError" => {
      status: 200,
      body: {succeededInvoices: [], failedInvoices: [{validation_errors: "API limit exceeded"}]}.to_json
    },
    "Integrations::Aggregator::ServerError" => {status: 503, body: ""},
    "Integrations::Aggregator::TimeoutError" => Net::ReadTimeout
  }.freeze

  def nango_action_endpoint
    NANGO_ACTION_ENDPOINT
  end

  # Each response is a WebMock response hash or a lambda taking the request. Several responses are
  # returned in order, the last one repeating.
  def stub_nango_action(*responses)
    stub_request(:post, NANGO_ACTION_ENDPOINT).to_return(*responses)
  end

  def stub_nango_action_failing_with(error_class)
    answer = RETRYABLE_ERROR_ANSWERS.fetch(error_class.name)
    return stub_request(:post, NANGO_ACTION_ENDPOINT).to_raise(answer) if answer.is_a?(Class)

    stub_nango_action(answer)
  end

  # A successful Anrok draft taxes answer that taxes each requested fee at `rate`.
  def anrok_draft_taxes_answer(rate: 0.1)
    lambda do |request|
      fees = JSON.parse(request.body).dig("input", 0, "fees").map do |fee|
        tax_amount_cents = (fee["amount_cents"].to_i * rate).round

        {
          item_key: fee["item_key"],
          item_id: fee["item_id"],
          item_code: fee["item_code"],
          amount_cents: fee["amount_cents"],
          tax_amount_cents:,
          tax_breakdown: [{name: "GST/HST", rate: rate.to_s, tax_amount: tax_amount_cents, type: "tax"}]
        }
      end

      {status: 200, body: {succeededInvoices: [{id: "inv_1", fees:}], failedInvoices: []}.to_json}
    end
  end
end
