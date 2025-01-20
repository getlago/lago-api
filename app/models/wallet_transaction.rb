# frozen_string_literal: true

class WalletTransaction < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :wallet

  # these two relationships are populated only for outbound transactions
  belongs_to :invoice, optional: true
  belongs_to :credit_note, optional: true

  STATUSES = [
    :pending,
    :settled
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

  scope :pending, -> { where(status: :pending) }
end

# == Schema Information
#
# Table name: wallet_transactions
#
#  id                                  :uuid             not null, primary key
#  amount                              :decimal(30, 5)   default(0.0), not null
#  credit_amount                       :decimal(30, 5)   default(0.0), not null
#  invoice_requires_successful_payment :boolean          default(FALSE), not null
#  metadata                            :jsonb
#  settled_at                          :datetime
#  source                              :integer          default("manual"), not null
#  status                              :integer          not null
#  transaction_status                  :integer          default("purchased"), not null
#  transaction_type                    :integer          not null
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  credit_note_id                      :uuid
#  invoice_id                          :uuid
#  wallet_id                           :uuid             not null
#
# Indexes
#
#  index_wallet_transactions_on_credit_note_id  (credit_note_id)
#  index_wallet_transactions_on_invoice_id      (invoice_id)
#  index_wallet_transactions_on_wallet_id       (wallet_id)
#
# Foreign Keys
#
#  fk_rails_...  (credit_note_id => credit_notes.id)
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (wallet_id => wallets.id)
#
