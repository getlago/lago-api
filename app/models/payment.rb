# frozen_string_literal: true

class Payment < ApplicationRecord
  include PaperTrailTraceable

  PAYABLE_PAYMENT_STATUS = %w[pending processing succeeded failed].freeze

  belongs_to :payable, polymorphic: true
  belongs_to :payment_provider, optional: true, class_name: 'PaymentProviders::BaseProvider'
  belongs_to :payment_provider_customer, optional: true, class_name: 'PaymentProviderCustomers::BaseCustomer'

  has_many :refunds
  has_many :integration_resources, as: :syncable

  PAYMENT_TYPES = {provider: 'provider', manual: 'manual'}.freeze
  attribute :payment_type, :string
  enum :payment_type, PAYMENT_TYPES, default: :provider, prefix: :payment_type
  validates :payment_type, presence: true
  validates :reference, presence: true, length: {maximum: 40}, if: -> { payment_type_manual? }
  validates :reference, absence: true, if: -> { payment_type_provider? }
  validate :max_invoice_paid_amount_cents, on: :create
  validate :payment_request_succeeded, on: :create

  delegate :customer, to: :payable

  enum payable_payment_status: PAYABLE_PAYMENT_STATUS.map { |s| [s, s] }.to_h

  scope :for_organization, lambda { |organization|
    invoices_join = ActiveRecord::Base.sanitize_sql_array(
      ["LEFT JOIN invoices AS i ON i.id = payments.payable_id AND payments.payable_type = 'Invoice' AND i.organization_id = ?", organization.id]
    )
    payment_requests_join = ActiveRecord::Base.sanitize_sql_array(
      ["LEFT JOIN payment_requests AS pr ON pr.id = payments.payable_id AND payments.payable_type = 'PaymentRequest' AND pr.organization_id = ?", organization.id]
    )
    joins(invoices_join).joins(payment_requests_join).where('i.id IS NOT NULL OR pr.id IS NOT NULL')
  }

  def should_sync_payment?
    return false unless payable.is_a?(Invoice)

    payable.finalized? && customer.integration_customers.accounting_kind.any? { |c| c.integration.sync_payments }
  end

  private

  def max_invoice_paid_amount_cents
    return if !payable.is_a?(Invoice) || payment_type_provider?
    return if amount_cents + payable.total_paid_amount_cents <= payable.total_amount_cents

    errors.add(:amount_cents, :greater_than)
  end

  def payment_request_succeeded
    return if !payable.is_a?(Invoice) || payment_type_provider?

    return unless payable.payment_requests.where(payment_status: 'succeeded').exists?

    errors.add(:base, :payment_request_is_already_succeeded)
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
