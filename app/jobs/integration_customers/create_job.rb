# frozen_string_literal: true

module IntegrationCustomers
  class CreateJob < ApplicationJob
    queue_as 'integrations'

    retry_on LagoHttpClient::HttpError, wait: :exponentially_longer, attempts: 3

    def perform(integration_customer_params:, integration:, customer:)
      result = IntegrationCustomers::CreateService.call(params: integration_customer_params, integration:, customer:)
      result.raise_if_error!
    end
  end
end
