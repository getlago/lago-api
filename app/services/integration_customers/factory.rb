# frozen_string_literal: true

module IntegrationCustomers
  class Factory
    def self.new_instance(integration:, customer:, subsidiary_id:)
      service_class(integration).new(integration:, customer:, subsidiary_id:)
    end

    def self.service_class(integration)
      case integration&.type&.to_s
      when 'Integrations::NetsuiteIntegration'
        IntegrationCustomers::NetsuiteService
      when 'Integrations::AnrokIntegration'
        IntegrationCustomers::AnrokService
      when 'Integrations::XeroIntegration'
        IntegrationCustomers::XeroService
      else
        raise(NotImplementedError)
      end
    end
  end
end
