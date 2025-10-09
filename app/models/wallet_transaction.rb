# frozen_string_literal: true

class WalletTransaction < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :wallet
  belongs_to :organization

  # these two relationships are populated only for outbound transactions
  belongs_to :invoice, optional: true
  belongs_to :credit_note, optional: true

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

  validates :priority, presence: true, inclusion: {in: 1..50}
  validates :name, length: {minimum: 1, maximum: 255}, allow_nil: true
  validates :invoice_requires_successful_payment, exclusion: [nil]

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
end

# == Schema Information
#
# Table name: wallet_transactions
#
#  id                                  :uuid             not null, primary key
#  amount                              :decimal(30, 5)   default(0.0), not null
#  credit_amount                       :decimal(30, 5)   default(0.0), not null
#  failed_at                           :datetime
#  invoice_requires_successful_payment :boolean          default(FALSE), not null
#  lock_version                        :integer          default(0), not null
#  metadata                            :jsonb
#  name                                :string(255)
#  priority                            :integer          default(50), not null
#  settled_at                          :datetime
#  source                              :integer          default("manual"), not null
#  status                              :integer          not null
#  transaction_status                  :integer          default("purchased"), not null
#  transaction_type                    :integer          not null
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  credit_note_id                      :uuid
#  invoice_id                          :uuid
#  organization_id                     :uuid             not null
#  wallet_id                           :uuid             not null
#
# Indexes
#
#  index_wallet_transactions_on_credit_note_id   (credit_note_id)
#  index_wallet_transactions_on_invoice_id       (invoice_id)
#  index_wallet_transactions_on_organization_id  (organization_id)
#  index_wallet_transactions_on_wallet_id        (wallet_id)
#
# Foreign Keys
#
#  fk_rails_...  (credit_note_id => credit_notes.id)
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (wallet_id => wallets.id)
#
