# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      module Crm
        class CreateCustomerAssociationJob < ApplicationJob
          queue_as 'integrations'

          retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 10
          retry_on RequestLimitError, wait: :polynomially_longer, attempts: 100

          def perform(invoice:)
            result = Integrations::Aggregator::Invoices::Crm::CreateCustomerAssociationService.call(invoice:)
            result.raise_if_error!
          end
        end
      end
    end
  end
end
