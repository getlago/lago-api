# frozen_string_literal: true

module IntegrationCustomers
  class UpdateJob < ApplicationJob
    queue_as 'integrations'

    retry_on LagoHttpClient::HttpError, wait: :exponentially_longer, attempts: 3

    def perform(integration_customer_params:, integration:, integration_customer:)
      result = IntegrationCustomers::UpdateService.call(
        params: integration_customer_params,
        integration:,
        integration_customer:
      )
      result.raise_if_error!
    end
  end
end
