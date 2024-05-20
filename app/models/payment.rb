# frozen_string_literal: true

class Payment < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :invoice
  belongs_to :payment_provider, optional: true, class_name: 'PaymentProviders::BaseProvider'
  belongs_to :payment_provider_customer, class_name: 'PaymentProviderCustomers::BaseCustomer'

  has_many :refunds
  has_many :integration_resources, as: :syncable

  delegate :customer, to: :invoice
end
