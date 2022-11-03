# frozen_string_literal: true

class Refund < ApplicationRecord
  belongs_to :payment
  belongs_to :credit_note
  belongs_to :payment_provider, class_name: 'PaymentProviders::BaseProvider'
  belongs_to :payment_provider_customer, class_name: 'PaymentProviderCustomers::BaseCustomer'
end
