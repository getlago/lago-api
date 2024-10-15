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
      integration_customer_service = IntegrationCustomers::Factory.new_instance(
        integration:, customer:, subsidiary_id:, **params
      )

      return result unless integration_customer_service

      sync_result = integration_customer_service.create

      return sync_result if sync_result.error

      result.integration_customer = sync_result.integration_customer
      result
    end

    def link_customer!
      new_integration_customer = IntegrationCustomers::BaseCustomer.create!(
        integration:,
        customer:,
        external_customer_id: params[:external_customer_id],
        type: customer_type,
        sync_with_provider: false
      )

      if integration&.type&.to_s == 'Integrations::NetsuiteIntegration'
        new_integration_customer.subsidiary_id = subsidiary_id
        new_integration_customer.save!
      end

      if integration&.type&.to_s == 'Integrations::HubspotIntegration'
        new_integration_customer.targeted_object = targeted_object
        new_integration_customer.save!
      end

      result.integration_customer = new_integration_customer
      result
    end
  end
end
