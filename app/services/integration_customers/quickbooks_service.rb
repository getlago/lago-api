# frozen_string_literal: true

module IntegrationCustomers
  class QuickbooksService < ::BaseService
    Result = BaseResult[:integration_customer]

    def initialize(integration:, customer:, subsidiary_id:, **params)
      @customer = customer
      @subsidiary_id = subsidiary_id
      @integration = integration
      @params = params&.with_indifferent_access

      super(nil)
    end

    # Creating the customer in QuickBooks is not wired yet: nothing is created or stored.
    def create
      result
    end

    private

    attr_reader :integration, :customer, :subsidiary_id, :params
  end
end
