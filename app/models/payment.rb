# frozen_string_literal: true

class Payment < ApplicationRecord
  include PaperTrailTraceable

  PAYABLE_PAYMENT_STATUS = %w[pending processing succeeded failed].freeze

  belongs_to :payable, polymorphic: true
  belongs_to :payment_provider, optional: true, class_name: 'PaymentProviders::BaseProvider'
  belongs_to :payment_provider_customer, optional: true, class_name: 'PaymentProviderCustomers::BaseCustomer'

  has_many :refunds
  has_many :integration_resources, as: :syncable

  PAYMENT_TYPES = {provider: "provider", manual: "manual"}
  attribute :payment_type, :string
  enum :payment_type, PAYMENT_TYPES, default: :provider, prefix: :payment_type
  validates :payment_type, presence: true
  validates :reference, presence: true, length: {maximum: 40}, if: -> { payment_type_manual? }
  validates :reference, absence: true, if: -> { payment_type_provider? }

  delegate :customer, to: :payable

  enum payable_payment_status: PAYABLE_PAYMENT_STATUS.map { |s| [s, s] }.to_h

  def should_sync_payment?
    return false unless payable.is_a?(Invoice)

    payable.finalized? && customer.integration_customers.accounting_kind.any? { |c| c.integration.sync_payments }
  end
end

# == Schema Information
#
# Table name: payments
#
#  id                           :uuid             not null, primary key
#  amount_cents                 :bigint           not null
#  amount_currency              :string           not null
#  payable_payment_status       :enum
#  payable_type                 :string           default("Invoice"), not null
#  payment_type                 :enum             default("provider"), not null
#  provider_payment_data        :jsonb
#  reference                    :string
#  status                       :string           not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  invoice_id                   :uuid
#  payable_id                   :uuid
#  payment_provider_customer_id :uuid
#  payment_provider_id          :uuid
#  provider_payment_id          :string
#
# Indexes
#
#  index_payments_on_invoice_id                    (invoice_id)
#  index_payments_on_payable_id_and_payable_type   (payable_id,payable_type) UNIQUE WHERE (payable_payment_status = ANY (ARRAY['pending'::payment_payable_payment_status, 'processing'::payment_payable_payment_status]))
#  index_payments_on_payable_type_and_payable_id   (payable_type,payable_id)
#  index_payments_on_payment_provider_customer_id  (payment_provider_customer_id)
#  index_payments_on_payment_provider_id           (payment_provider_id)
#  index_payments_on_payment_type                  (payment_type)
#
# Foreign Keys
#
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (payment_provider_id => payment_providers.id)
#
