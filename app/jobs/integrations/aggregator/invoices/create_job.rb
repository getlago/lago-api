# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class CreateJob < ApplicationJob
        queue_as 'integrations'

        retry_on LagoHttpClient::HttpError, wait: :exponentially_longer, attempts: 3

        def perform(invoice:)
          result = Integrations::Aggregator::Invoices::CreateService.call(invoice:)
          result.raise_if_error!
        end
      end
    end
  end
end
