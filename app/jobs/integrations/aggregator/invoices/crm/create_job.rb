# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      module Crm
        class CreateJob < ApplicationJob
          queue_as 'integrations'

          retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 10
          retry_on RequestLimitError, wait: :polynomially_longer, attempts: 10

          def perform(invoice:)
            result = Integrations::Aggregator::Invoices::Crm::CreateService.call(invoice:)

            if result.success?
              Integrations::Aggregator::Invoices::Crm::CreateCustomerAssociationJob.perform_later(invoice:)
            end

            result.raise_if_error!
          end
        end
      end
    end
  end
end
