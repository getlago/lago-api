# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class CreateJob < ApplicationJob
        queue_as 'integrations'

        retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 3
        retry_on RequestLimitError, wait: :polynomially_longer, attempts: 100

        def perform(invoice:)
          result = Integrations::Aggregator::Invoices::CreateService.call(invoice:)
          result.raise_if_error!
        end
      end
    end
  end
end
