# frozen_string_literal: true

class Payment < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :payable, polymorphic: true
  belongs_to :payment_request, optional: true
  belongs_to :payment_provider, optional: true, class_name: 'PaymentProviders::BaseProvider'
  belongs_to :payment_provider_customer, class_name: 'PaymentProviderCustomers::BaseCustomer'

  has_many :refunds
  has_many :integration_resources, as: :syncable

  delegate :customer, to: :payable

  def should_sync_payment?
    return false unless payable.is_a?(Invoice)

    payable.finalized? && customer.integration_customers.accounting_kind.any? { |c| c.integration.sync_payments }
  end
end
