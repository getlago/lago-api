# frozen_string_literal: true

module IntegrationCustomers
  class CreateService < BaseService
    def initialize(params:, integration:, customer:)
      @customer = customer
      super(params:, integration:)
    end

    def call
      result = super
      return result if result.error

      res = if external_customer_id.present?
        link_customer!
      elsif sync_with_provider
        sync_customer!
      end
      return res if res&.error

      result
    end

    private

    attr_reader :customer

    def sync_customer!
      if integration.type == 'Integrations::NetsuiteIntegration'
        create_result = Integrations::Aggregator::Contacts::CreateService.call(integration:, customer:, subsidiary_id:)
        return create_result if create_result.error
      end

      new_integration_customer = IntegrationCustomers::BaseCustomer.create!(
        integration:,
        customer:,
        external_customer_id: create_result.contact_id,
        type: customer_type,
        subsidiary_id:,
        sync_with_provider: true
      )

      result.integration_customer = new_integration_customer
      result
    end

    def link_customer!
      new_integration_customer = IntegrationCustomers::BaseCustomer.create!(
        integration:,
        customer:,
        external_customer_id: params[:external_customer_id],
        type: customer_type,
        subsidiary_id:,
        sync_with_provider: false
      )

      result.integration_customer = new_integration_customer
      result
    end
  end
end
