# frozen_string_literal: true

module IntegrationCustomers
  class CreateOrUpdateService < ::BaseService
    def initialize(integration_customers:, customer:, new_customer:)
      @integration_customers = integration_customers&.map { |c| c.to_h.deep_symbolize_keys }
      @customer = customer
      @new_customer = new_customer

      super(nil)
    end

    def call
      return unless integration_customers

      integration_customers.each do |int_customer_params|
        @integration_customer_params = int_customer_params

        next unless integration
        next if skip_creating_integration_customer?

        if remove_integration_customer?
          integration_customer.destroy!
          next
        end

        if create_integration_customer?
          IntegrationCustomers::CreateJob.perform_later(integration_customer_params:, integration:, customer:)
        elsif update_integration_customer?
          IntegrationCustomers::UpdateJob.perform_later(
            integration_customer_params:,
            integration:,
            integration_customer:
          )
        end
      end
    end

    private

    attr_reader :integration_customer_params, :customer, :new_customer, :integration_customers

    def create_integration_customer?
      (new_customer && integration_customer_params[:sync_with_provider]) ||
        (new_customer && integration_customer_params[:external_customer_id]) ||
        (!new_customer && integration_customer.nil? && integration_customer_params[:sync_with_provider]) ||
        (!new_customer && integration_customer.nil? && integration_customer_params[:external_customer_id])
    end

    def update_integration_customer?
      !new_customer && integration_customer
    end

    def remove_integration_customer?
      !new_customer &&
        integration_customer &&
        integration_customer_params[:external_customer_id].blank?
    end

    def skip_creating_integration_customer?
      integration_customer.nil? &&
        integration_customer_params.blank?
    end

    def integration
      return @integration if defined? @integration
      return nil unless integration_customer_params &&
        integration_customer_params[:integration_type] &&
        integration_customer_params[:integration_code]

      type = Integrations::BaseIntegration.integration_type(integration_customer_params[:integration_type])
      code = integration_customer_params[:integration_code]

      @integration = Integrations::BaseIntegration.find_by(type:, code:)
    end

    def integration_customer
      @integration_customer ||= IntegrationCustomers::BaseCustomer.find_by(integration:, customer:)
    end
  end
end
