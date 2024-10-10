# frozen_string_literal: true

module IntegrationCustomers
  class HubspotService < ::BaseService
    def initialize(integration:, customer:, subsidiary_id:)
      @customer = customer
      @subsidiary_id = subsidiary_id
      @integration = integration

      super(nil)
    end

    def create
      create_result = create_service_class.call(
        integration:,
        customer:,
        subsidiary_id: nil
      )

      return create_result if create_result.error

      new_integration_customer = IntegrationCustomers::BaseCustomer.create!(
        integration:,
        customer:,
        external_customer_id: create_result.contact_id,
        email: create_result.email,
        type: 'IntegrationCustomers::HubspotCustomer',
        sync_with_provider: true
      )

      result.integration_customer = new_integration_customer
      result
    end

    private

    attr_reader :integration, :customer, :subsidiary_id

    def create_service_class
      @create_service_class ||= if customer.customer_type_individual?
        Integrations::Aggregator::Contacts::CreateService
      else
        Integrations::Aggregator::Companies::CreateService
      end
    end
  end
end
