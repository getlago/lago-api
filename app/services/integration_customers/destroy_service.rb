# frozen_string_literal: true

module IntegrationCustomers
  class DestroyService < ::BaseService
    Result = BaseResult[:integration_customer]

    def initialize(integration_customer:)
      @integration_customer = integration_customer

      super
    end

    def call
      return result.not_found_failure!(resource: "integration_customer") unless integration_customer

      integration_customer.destroy!

      result.integration_customer = integration_customer
      result
    end

    private

    attr_reader :integration_customer
  end
end
