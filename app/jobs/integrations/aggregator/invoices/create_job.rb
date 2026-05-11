# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class CreateJob < ApplicationJob
        include ConcurrencyThrottlable

        # NOTE: NetSuite waits longer to avoid racing in-flight Nango calls; others use polynomial backoff.
        # 6 minutes covers Nango's 5-minute upstream NetSuite action timeout with a safety margin.
        DELAY_BY_PROVIDER_KEY = {
          "netsuite" => 6.minutes
        }.freeze

        queue_as "integrations"

        unique :until_executed, on_conflict: :log

        retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 3
        retry_on RequestLimitError, wait: :polynomially_longer, attempts: 100
        retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25
        discard_on BaseService::NonRetryableFailure

        # NOTE: `executions_for` and `determine_delay` are ActiveJob internals used by `retry_on`,
        # not part of its public API. We reuse them so the per-exception execution counter and jitter
        # behave identically to a normal `retry_on`. Revisit this block on Rails upgrades.
        rescue_from(Net::ReadTimeout) do |error|
          attempts = 6
          executions_count = executions_for([Net::ReadTimeout])

          if executions_count >= attempts
            instrument :retry_stopped, error:
            raise
          end

          wait_strategy = DELAY_BY_PROVIDER_KEY.fetch(integration_provider_key, :polynomially_longer)

          retry_job(
            wait: determine_delay(seconds_or_duration_or_algorithm: wait_strategy, executions: executions_count),
            error: error
          )
        end

        def perform(invoice:)
          if executions > 1
            find_result = Integrations::Aggregator::Invoices::FindService.call(invoice:)
            find_result.raise_if_error!
            return if find_result.external_id.present?
          end

          result = Integrations::Aggregator::Invoices::CreateService.call(invoice:)
          result.raise_if_error!
        end

        private

        def integration_provider_key
          invoice = arguments.first[:invoice]
          invoice&.customer&.integration_customers&.accounting_kind&.first&.integration&.provider_key
        end
      end
    end
  end
end
