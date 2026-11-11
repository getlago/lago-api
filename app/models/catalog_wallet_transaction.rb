# frozen_string_literal: true

class CatalogWalletTransaction < ApplicationRecord
  include PaperTrailTraceable

  DIRECTIONS = {
    inbound: "inbound",
    outbound: "outbound"
  }.freeze

  STATUSES = {
    pending: "pending",
    settled: "settled",
    failed: "failed"
  }.freeze

  REASONS = {
    top_up: "top_up",
    credit_allocation: "credit_allocation",
    invoice_void: "invoice_void",
    invoice_application: "invoice_application",
    void: "void"
  }.freeze

  belongs_to :organization
  belongs_to :catalog_wallet, -> { with_discarded }
  belongs_to :credit_allocation, -> { with_discarded }, class_name: "CatalogWalletCreditAllocation", optional: true
  belongs_to :invoice, optional: true

  enum :direction, DIRECTIONS, validate: true
  enum :status, STATUSES, validate: true
  enum :reason, REASONS, validate: true
  enum :allocation_type, CreditAllocationRule::TRIGGERS, validate: {allow_nil: true}, prefix: true

  validates :priority, inclusion: {in: 1..CatalogWalletSettings::LOWEST_PRIORITY}
  validates :credit_amount_cents, numericality: {only_integer: true, greater_than: 0}
  validates :purchase_amount_cents, numericality: {only_integer: true, greater_than_or_equal_to: 0}, allow_nil: true
  validates :remaining_credit_amount_cents,
    numericality: {only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: :credit_amount_cents},
    allow_nil: true

  scope :in_spending_order, -> { order(:priority, Arel.sql("purchase_amount_cents > 0"), :created_at, :id) }
end

# == Schema Information
#
# Table name: catalog_wallet_transactions
# Database name: primary
#
#  id                                  :uuid             not null, primary key
#  allocation_type                     :enum
#  credit_amount_cents                 :bigint           not null
#  direction                           :enum             not null
#  failed_at                           :datetime
#  idempotency_key                     :string
#  invoice_requires_successful_payment :boolean
#  priority                            :integer          default(50), not null
#  purchase_amount_cents               :bigint
#  reason                              :enum             not null
#  remaining_credit_amount_cents       :bigint
#  request_digest                      :string
#  settled_at                          :datetime
#  source_cycle_started_at             :datetime
#  status                              :enum             not null
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  catalog_wallet_id                   :uuid             not null
#  credit_allocation_id                :uuid
#  invoice_id                          :uuid
#  organization_id                     :uuid             not null
#
# Indexes
#
#  index_catalog_wallet_transactions_in_spending_order              (catalog_wallet_id, priority, ((purchase_amount_cents > 0)), created_at, id) WHERE ((direction = 'inbound'::catalog_wallet_transaction_direction) AND (status = 'settled'::catalog_wallet_transaction_status) AND (remaining_credit_amount_cents > 0))
#  index_catalog_wallet_transactions_on_catalog_wallet_id           (catalog_wallet_id)
#  index_catalog_wallet_transactions_on_grant_occurrence            (credit_allocation_id,source_cycle_started_at) UNIQUE WHERE (source_cycle_started_at IS NOT NULL)
#  index_catalog_wallet_transactions_on_invoice_id                  (invoice_id)
#  index_catalog_wallet_transactions_on_organization_id             (organization_id)
#  index_catalog_wallet_transactions_on_wallet_and_idempotency_key  (catalog_wallet_id,idempotency_key) UNIQUE WHERE (idempotency_key IS NOT NULL)
#  index_catalog_wallet_transactions_one_pending_ongoing_balance    (catalog_wallet_id) UNIQUE WHERE ((allocation_type = 'ongoing_balance'::catalog_wallet_transaction_allocation_type) AND (status = 'pending'::catalog_wallet_transaction_status))
#
# Foreign Keys
#
#  fk_rails_...  (catalog_wallet_id => catalog_wallets.id)
#  fk_rails_...  (credit_allocation_id => catalog_wallet_credit_allocations.id)
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (organization_id => organizations.id)
#
