# frozen_string_literal: true

class Payment < ApplicationRecord
  belongs_to :invoice
  belongs_to :payment_provider, optional: true, class_name: 'PaymentProviders::BaseProvider'
  belongs_to :payment_provider_customer, class_name: 'PaymentProviderCustomers::BaseCustomer'

  has_many :refunds
end
