# frozen_string_literal: true

module PaymentProviderCustomers
  class BaseCustomer < ApplicationRecord
    self.table_name = 'payment_provider_customers'

    validates :external_customer_id, presence: true

    def push_to_settings(key:, value:)
      self.settings ||= {}
      settings[key] = value
    end

    def get_from_settings(key)
      (settings || {})[key]
    end
  end
end
