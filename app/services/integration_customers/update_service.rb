# frozen_string_literal: true

module IntegrationCustomers
  class UpdateService < BaseService
    def initialize(params:, integration:, integration_customer:)
      @integration_customer = integration_customer
      super(params:, integration:)
    end

    def call
      result = super
      return result if result.error

      return result.not_found_failure!(resource: 'integration_customer') unless integration_customer

      if sync_with_provider
        update_result = Integrations::Aggregator::Contacts::UpdateService.call(integration:, integration_customer:)
        integration_customer.update!(subsidiary_id:)

        return update_result if update_result.error
      elsif external_customer_id.present?
        integration_customer.update!(external_customer_id:)
      end

      result.integration_customer = integration_customer
      result
    end

    private

    attr_reader :integration_customer

    delegate :customer, to: :integration_customer
  end
end
