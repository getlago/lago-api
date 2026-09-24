# frozen_string_literal: true

module X402
  # D3: one row per payment Lago verified and asked the facilitator to settle; the idempotency anchor.
  class Settlement < ApplicationRecord
    KINDS = {credit_purchase: "credit_purchase", invoice_payment: "invoice_payment"}.freeze
    STATUSES = {pending: "pending", settled: "settled", failed: "failed"}.freeze

    belongs_to :organization
    belongs_to :x402_connection, -> { with_discarded }, class_name: "X402::Connection" # connections are soft-deleted
    belongs_to :customer, optional: true
    belongs_to :subscription, optional: true
    belongs_to :wallet_transaction, optional: true

    enum :kind, KINDS, validate: true
    enum :status, STATUSES, validate: true
  end
end

# == Schema Information
#
# Table name: x402_settlements
# Database name: primary
#
#  id                    :uuid             not null, primary key
#  asset                 :string           not null
#  error_reason          :string
#  kind                  :enum             not null
#  network               :string           not null
#  payee_address         :string           not null
#  payer_address         :string           not null
#  payload               :jsonb            not null
#  payment_digest        :string           not null
#  purchase_settings     :jsonb
#  reconcile_after       :datetime
#  settled_amount_atomic :decimal(38, )    not null
#  settled_amount_cents  :bigint           not null
#  status                :enum             default("pending"), not null
#  transaction_hash      :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  customer_id           :uuid
#  organization_id       :uuid             not null
#  subscription_id       :uuid
#  wallet_transaction_id :uuid
#  x402_connection_id    :uuid             not null
#
# Indexes
#
#  index_x402_settlements_on_customer_id                         (customer_id)
#  index_x402_settlements_on_org_network_and_transaction_hash    (organization_id,network,transaction_hash) UNIQUE WHERE (transaction_hash IS NOT NULL)
#  index_x402_settlements_on_organization_id                     (organization_id)
#  index_x402_settlements_on_organization_id_and_payment_digest  (organization_id,payment_digest) UNIQUE WHERE (status = ANY (ARRAY['pending'::x402_settlement_status, 'settled'::x402_settlement_status]))
#  index_x402_settlements_on_x402_connection_id                  (x402_connection_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#  fk_rails_...  (wallet_transaction_id => wallet_transactions.id)
#  fk_rails_...  (x402_connection_id => x402_connections.id)
#
