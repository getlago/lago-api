# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class CreateJob < ApplicationJob
        include ConcurrencyThrottlable

        # NOTE: NetSuite waits longer to avoid racing in-flight Nango calls; others use polynomial backoff.
        READ_TIMEOUT_WAIT_BY_PROVIDER_KEY = {
          "netsuite" => 5.minutes
        }.freeze

        queue_as "integrations"

        unique :until_executed, on_conflict: :log

        retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 3
        retry_on RequestLimitError, wait: :polynomially_longer, attempts: 100
        retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25
        discard_on BaseService::NonRetryableFailure

        rescue_from(Net::ReadTimeout) do |error|
          attempts = 6
          executions_count = executions_for([Net::ReadTimeout])
          raise error if executions_count >= attempts

          wait_strategy = READ_TIMEOUT_WAIT_BY_PROVIDER_KEY.fetch(integration_provider_key, :polynomially_longer)

          retry_job(
            wait: determine_delay(seconds_or_duration_or_algorithm: wait_strategy, executions: executions_count),
            error: error
          )
        end

        def perform(invoice:)
          @invoice = invoice
          result = Integrations::Aggregator::Invoices::CreateService.call(invoice:)
          result.raise_if_error!
        end

        private

        def integration_provider_key
          @invoice&.customer&.integration_customers&.accounting_kind&.first&.integration&.provider_key
        end
      end
    end
  end
end
