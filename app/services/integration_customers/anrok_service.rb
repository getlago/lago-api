# frozen_string_literal: true

module IntegrationCustomers
  class AnrokService < ::BaseService
    def initialize(integration:, customer:, subsidiary_id:)
      @customer = customer
      @subsidiary_id = subsidiary_id
      @integration = integration

      super(nil)
    end

    def create
      # For Anrok real customer sync happens with the first document sync. In the meantime,
      # integration customer object needs to be stored on Lago side
      new_integration_customer = IntegrationCustomers::BaseCustomer.create!(
        integration:,
        customer:,
        type: 'IntegrationCustomers::AnrokCustomer',
        sync_with_provider: true
      )

      result.integration_customer = new_integration_customer
      result
    end

    private

    attr_reader :integration, :customer, :subsidiary_id
  end
end
