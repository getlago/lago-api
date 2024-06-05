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

      integration_customer.update!(external_customer_id:) if external_customer_id.present?

      if sync_with_provider
        integration_customer.subsidiary_id = subsidiary_id if subsidiary_id.present?

        update_result = Integrations::Aggregator::Contacts::UpdateService.call(integration:, integration_customer:)
        return update_result unless update_result.success?

        integration_customer.save!
      end

      result.integration_customer = integration_customer
      result
    end

    private

    attr_reader :integration_customer

    delegate :customer, to: :integration_customer
  end
end
