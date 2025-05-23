# frozen_string_literal: true

module Integrations
  module Hubspot
    module Subscriptions
      class DeployObjectJob < ApplicationJob
        queue_as "integrations"

        retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 3
        retry_on Integrations::Aggregator::RequestLimitError, wait: :polynomially_longer, attempts: 100
        retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25

        def perform(integration:)
          result = Integrations::Hubspot::Subscriptions::DeployObjectService.call(integration:)
          result.raise_if_error!
        end
      end
    end
  end
end
