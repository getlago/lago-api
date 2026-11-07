# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class VoidService < BaseService
        Result = BaseResult[:invoice_id]

        def action_path
          "v1/#{provider}/invoices/void"
        end

        def call
          return result unless integration
          return result unless integration.sync_invoices
          return result unless provider == "netsuite"
          return result unless invoice.voided?

          throttle!(:netsuite)

          http_client.put_with_response(payload.void_body, headers)

          result.invoice_id = invoice.id
          result
        rescue LagoHttpClient::HttpError => e
          raise RequestLimitError.new(e) if request_limit_error?(e)

          code = code(e)
          message = message(e)

          deliver_error_webhook(customer:, code:, message:)

          raise e if retryable_error?(e)

          result.non_retryable_failure!(code:, message:)
        end
      end
    end
  end
end
