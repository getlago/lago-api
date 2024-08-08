# frozen_string_literal: true

class Payment < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :invoice
  belongs_to :payment_provider, optional: true, class_name: 'PaymentProviders::BaseProvider'
  belongs_to :payment_provider_customer, class_name: 'PaymentProviderCustomers::BaseCustomer'

  has_many :refunds
  has_many :integration_resources, as: :syncable

  delegate :customer, to: :invoice

  def should_sync_payment?
    invoice.finalized? && customer.integration_customers.accounting_kind.any? { |c| c.integration.sync_payments }
  end
end

# == Schema Information
#
# Table name: payments
#
#  id                           :uuid             not null, primary key
#  amount_cents                 :bigint           not null
#  amount_currency              :string           not null
#  status                       :string           not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  invoice_id                   :uuid             not null
#  payment_provider_customer_id :uuid
#  payment_provider_id          :uuid
#  provider_payment_id          :string           not null
#
# Indexes
#
#  index_payments_on_invoice_id                    (invoice_id)
#  index_payments_on_payment_provider_customer_id  (payment_provider_customer_id)
#  index_payments_on_payment_provider_id           (payment_provider_id)
#
# Foreign Keys
#
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (payment_provider_id => payment_providers.id)
#
