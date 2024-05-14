# frozen_string_literal: true

module Integrations
  module Aggregator
    module SalesOrders
      class CreateJob < ApplicationJob
        queue_as 'integrations'

        retry_on LagoHttpClient::HttpError, wait: :exponentially_longer, attempts: 3

        # TODO:
        def perform(invoice:)
        end
      end
    end
  end
end
