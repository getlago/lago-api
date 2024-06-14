# frozen_string_literal: true

module V1
  class IntegrationCustomerSerializer < ModelSerializer
    def serialize
      base_response = {
        lago_id: model.id,
        external_customer_id: model.external_customer_id,
        type:
      }

      base_response.merge!(model&.settings || {})
    end

    private

    def type
      case model.type
      when 'IntegrationCustomers::NetsuiteCustomer'
        'netsuite'
      when 'IntegrationCustomers::AnrokCustomer'
        'anrok'
      end
      end
    end
  end
end
