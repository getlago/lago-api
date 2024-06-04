# frozen_string_literal: true

module Integrations
  module Aggregator
    module Payments
      class CreateJob < ApplicationJob
        queue_as 'integrations'

        retry_on LagoHttpClient::HttpError, wait: :exponentially_longer, attempts: 5

        def perform(payment:)
          result = Integrations::Aggregator::Payments::CreateService.call(payment:)
          result.raise_if_error!
        end
      end
    end
  end
end
