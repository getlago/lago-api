# frozen_string_literal: true

module PaymentProviderCustomers
  class GocardlessCustomer < BaseCustomer
    def mandate_id
      get_from_settings('mandate_id')
    end

    def mandate_id=(mandate_id)
      push_to_settings(key: 'mandate_id', value: mandate_id)
    end
  end
end
