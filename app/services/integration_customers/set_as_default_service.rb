# frozen_string_literal: true

module IntegrationCustomers
  class SetAsDefaultService < ::BaseService
    Result = BaseResult[:integration_customer]

    def initialize(integration_customer:)
      @integration_customer = integration_customer

      super
    end

    def call
      return result.not_found_failure!(resource: "integration_customer") unless integration_customer

      if integration_customer.is_default?
        result.integration_customer = integration_customer
        return result
      end

      ActiveRecord::Base.transaction do
        integration_customer.customer.integration_customers
          .where(category: integration_customer.category)
          .where.not(id: integration_customer.id)
          .update_all(is_default: false, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        integration_customer.update!(is_default: true)
      end

      result.integration_customer = integration_customer

      result
    end

    private

    attr_reader :integration_customer
  end
end
