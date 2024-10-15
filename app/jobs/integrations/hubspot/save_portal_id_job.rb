# frozen_string_literal: true

module Integrations
  module Hubspot
    class SavePortalIdJob < ApplicationJob
      queue_as 'integrations'

      retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 3

      def perform(integration:)
        result = Integrations::Hubspot::SavePortalIdService.call(integration:)
        result.raise_if_error!
      end
    end
  end
end
