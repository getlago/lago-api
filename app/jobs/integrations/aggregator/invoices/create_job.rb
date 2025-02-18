# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class CreateJob < ApplicationJob
        include ConcurrencyThrottlable

        queue_as "integrations"

        unique :until_executed, on_conflict: :log

        retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 3
        retry_on Net::ReadTimeout, wait: :polynomially_longer, attempts: 6
        retry_on RequestLimitError, wait: :polynomially_longer, attempts: 100
        retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25

        def perform(invoice:)
          result = Integrations::Aggregator::Invoices::CreateService.call(invoice:)
          result.raise_if_error!
        end
      end
    end
  end
end
