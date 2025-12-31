# frozen_string_literal: true

class WalletTransaction < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :wallet
  belongs_to :organization

  # these two relationships are populated only for outbound transactions
  belongs_to :invoice, optional: true
  belongs_to :credit_note, optional: true

  has_many :consumptions,
    class_name: "WalletTransactionConsumption",
    foreign_key: :inbound_wallet_transaction_id,
    dependent: :destroy

  has_many :fundings,
    class_name: "WalletTransactionConsumption",
    foreign_key: :outbound_wallet_transaction_id,
    dependent: :destroy

  has_many :consuming_transactions,
    through: :consumptions,
    source: :outbound_wallet_transaction

  has_many :source_transactions,
    through: :fundings,
    source: :inbound_wallet_transaction

  has_many :applied_invoice_custom_sections,
    class_name: "WalletTransaction::AppliedInvoiceCustomSection",
    dependent: :destroy
  has_many :selected_invoice_custom_sections,
    through: :applied_invoice_custom_sections,
    source: :invoice_custom_section

  STATUSES = [
    :pending,
    :settled,
    :failed
  ].freeze

  TRANSACTION_STATUSES = [
    :purchased,
    :granted,
    :voided,
    :invoiced
  ].freeze

  TRANSACTION_TYPES = [
    :inbound,
    :outbound
  ].freeze

  SOURCES = [
    :manual,
    :interval,
    :threshold
  ].freeze

  enum :status, STATUSES
  enum :transaction_status, TRANSACTION_STATUSES
  enum :transaction_type, TRANSACTION_TYPES
  enum :source, SOURCES

  validates :status, :transaction_type, :source, :transaction_status, presence: true
  validates :priority, presence: true, inclusion: {in: 1..50}
  validates :name, length: {minimum: 1, maximum: 255}, allow_nil: true
  validates :invoice_requires_successful_payment, exclusion: [nil]
  validate :remaining_amount_cents_only_for_inbound

  delegate :customer, to: :wallet

  scope :pending, -> { where(status: :pending) }

  def self.order_by_priority
    order(:priority)
      .in_order_of(:transaction_status, [:granted, :purchased, :voided, :invoiced])
      .order(:created_at)
  end

  def amount_cents
    amount * wallet.currency_for_balance.subunit_to_unit
  end

  def unit_amount_cents
    wallet.rate_amount * wallet.currency_for_balance.subunit_to_unit
  end

  def mark_as_failed!(timestamp = Time.zone.now)
    return if failed?

    update!(status: :failed, failed_at: timestamp)
  end

  private

  def remaining_amount_cents_only_for_inbound
    return if remaining_amount_cents.nil?
    return if inbound?

    errors.add(:remaining_amount_cents, :only_for_inbound)
  end
end

# == Schema Information
#
# Table name: wallet_transactions
# Database name: primary
#
#  id                                  :uuid             not null, primary key
#  amount                              :decimal(30, 5)   default(0.0), not null
#  credit_amount                       :decimal(30, 5)   default(0.0), not null
#  failed_at                           :datetime
#  invoice_requires_successful_payment :boolean          default(FALSE), not null
#  lock_version                        :integer          default(0), not null
#  metadata                            :jsonb
#  name                                :string(255)
#  payment_method_type                 :enum             default("provider"), not null
#  priority                            :integer          default(50), not null
#  remaining_amount_cents              :bigint
#  settled_at                          :datetime
#  skip_invoice_custom_sections        :boolean          default(FALSE), not null
#  source                              :integer          default("manual"), not null
#  status                              :integer          not null
#  transaction_status                  :integer          default("purchased"), not null
#  transaction_type                    :integer          not null
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  credit_note_id                      :uuid
#  invoice_id                          :uuid
#  organization_id                     :uuid             not null
#  payment_method_id                   :uuid
#  wallet_id                           :uuid             not null
#
# Indexes
#
#  idx_wallet_transactions_available_inbound       (wallet_id) WHERE ((remaining_amount_cents > 0) AND (transaction_type = 0) AND (status = 1))
#  index_wallet_transactions_on_credit_note_id     (credit_note_id)
#  index_wallet_transactions_on_invoice_id         (invoice_id)
#  index_wallet_transactions_on_organization_id    (organization_id)
#  index_wallet_transactions_on_payment_method_id  (payment_method_id)
#  index_wallet_transactions_on_wallet_id          (wallet_id)
#
# Foreign Keys
#
#  fk_rails_...  (credit_note_id => credit_notes.id)
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (payment_method_id => payment_methods.id)
#  fk_rails_...  (wallet_id => wallets.id)
#
