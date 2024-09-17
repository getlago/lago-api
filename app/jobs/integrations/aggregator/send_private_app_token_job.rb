# frozen_string_literal: true

module Integrations
  module Aggregator
    class SendPrivateAppTokenJob < ApplicationJob
      queue_as 'integrations'

      retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 3

      def perform(integration:)
        result = Integrations::Aggregator::SendPrivateAppTokenService.call(integration:)
        result.raise_if_error!
      end
    end
  end
end
