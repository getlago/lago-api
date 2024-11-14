# frozen_string_literal: true

module Integrations
  module Aggregator
    module Subscriptions
      module Crm
        class CreateCustomerAssociationJob < ApplicationJob
          queue_as 'integrations'

          unique :until_executed

          retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 10
          retry_on RequestLimitError, wait: :polynomially_longer, attempts: 100

          def perform(subscription:)
            result = Integrations::Aggregator::Subscriptions::Crm::CreateCustomerAssociationService.call(subscription:)
            result.raise_if_error!
          end
        end
      end
    end
  end
end
