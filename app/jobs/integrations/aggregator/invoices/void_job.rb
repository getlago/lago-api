# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class VoidJob < ApplicationJob
        include ConcurrencyThrottlable
        include Integrations::Aggregator::ProviderDelayedRetry

        queue_as "integrations"

        unique :until_executed, on_conflict: :log

        retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 3
        retry_on RequestLimitError, wait: :polynomially_longer, attempts: 100
        retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25
        retry_on Integrations::Aggregator::BasePayload::Failure, wait: :polynomially_longer, attempts: 10
        discard_on BaseService::NonRetryableFailure

        def perform(invoice:)
          Integrations::Aggregator::Invoices::VoidService.call!(invoice:)
        end
      end
    end
  end
end
