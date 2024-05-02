# frozen_string_literal: true

module IntegrationMappings
  class Factory
    def self.new_instance(integration:)
      service_class(integration)
    end

    def self.service_class(integration)
      case integration&.type&.to_s
      when 'Integrations::NetsuiteIntegration'
        IntegrationMappings::NetsuiteMapping
      else
        raise(NotImplementedError)
      end
    end
  end
end
