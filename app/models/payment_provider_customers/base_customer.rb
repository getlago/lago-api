# frozen_string_literal: true

module PaymentProviderCustomers
  class BaseCustomer < ApplicationRecord
    self.table_name = 'payment_provider_customers'

    belongs_to :customer
    belongs_to :payment_provider, optional: true

    has_many :payments

    def push_to_settings(key:, value:)
      self.settings ||= {}
      settings[key] = value
    end

    def get_from_settings(key)
      (settings || {})[key]
    end
  end
end
