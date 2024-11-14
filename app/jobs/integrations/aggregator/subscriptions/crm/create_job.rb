# frozen_string_literal: true

module Integrations
  module Aggregator
    module Subscriptions
      module Crm
        class CreateJob < ApplicationJob
          queue_as 'integrations'

          unique :until_executed

          retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 10
          retry_on Integrations::Aggregator::BasePayload::Failure, wait: :polynomially_longer, attempts: 10
          retry_on RequestLimitError, wait: :polynomially_longer, attempts: 100

          def perform(subscription:)
            result = Integrations::Aggregator::Subscriptions::Crm::CreateService.call(subscription:)

            if result.success?
              Integrations::Aggregator::Subscriptions::Crm::CreateCustomerAssociationJob.perform_later(subscription:)
            end

            result.raise_if_error!
          end
        end
      end
    end
  end
end
