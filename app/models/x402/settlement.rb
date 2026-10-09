# frozen_string_literal: true

module X402
  class Settlement < ApplicationRecord
    KINDS = {credit_purchase: "credit_purchase", invoice_payment: "invoice_payment"}.freeze
    STATUSES = {pending: "pending", settled: "settled", failed: "failed"}.freeze
    SETTLED_BY = {lago: "lago", merchant: "merchant"}.freeze

    belongs_to :organization
    belongs_to :x402_connection, -> { with_discarded }, class_name: "X402::Connection", inverse_of: :settlements
    belongs_to :customer, -> { with_discarded }, optional: true
    belongs_to :subscription, optional: true
    belongs_to :wallet_transaction, optional: true
    belongs_to :payment, optional: true, inverse_of: :x402_settlement
    belongs_to :invoice, optional: true

    enum :kind, KINDS, validate: true
    enum :status, STATUSES, validate: true
    enum :settled_by, SETTLED_BY, prefix: true, validate: true

    attr_readonly :payer_address, :payee_address, :payment_digest, :purchase_settings, :invoice_id

    before_validation :normalize_addresses, on: :create

    validates :network, inclusion: {in: X402::Network::NETWORKS.keys}
    validates :asset, :payment_digest, presence: true
    validates :settled_amount_atomic, numericality: {only_integer: true, greater_than: 0}
    validates :settled_amount_cents, numericality: {only_integer: true}
    validates :invoice, presence: true, if: :invoice_payment?
    validates :purchase_settings, presence: true, if: :credit_purchase?
    validate :validate_addresses
    validate :validate_connection, on: :create
    validate :validate_invoice, on: :create

    scope :pending_reconciliation, -> { pending.where(reconcile_after: ..Time.current) }

    private

    def family
      if X402::Network::NETWORKS.key?(network)
        X402::Network.family_of_network(network)
      end
    end

    def normalize_addresses
      if family
        self.payer_address = X402::Network.normalize_address(payer_address, family:)
        self.payee_address = X402::Network.normalize_address(payee_address, family:)
        self.asset = X402::Network.normalize_address(asset, family:)
      end
    end

    def validate_addresses
      if family
        %i[payer_address payee_address]
          .reject { |attribute| X402::Network.valid_address?(self[attribute], family:) }
          .each { |attribute| errors.add(attribute, :invalid_format) }
      end
    end

    def validate_connection
      if x402_connection && x402_connection.organization_id != organization_id
        errors.add(:x402_connection, :must_belong_to_same_organization)
      end

      if x402_connection && family
        validate_connection_terms
      end
    end

    def validate_invoice
      if invoice && invoice.organization_id != organization_id
        errors.add(:invoice, :must_belong_to_same_organization)
      end
    end

    def validate_connection_terms
      if x402_connection.networks.exclude?(network)
        errors.add(:network, :not_offered_by_connection)
      end

      if X402::Network.valid_address?(payee_address, family:) && payee_address != x402_connection.payout_addresses[family.to_s]
        errors.add(:payee_address, :not_connection_payout_address)
      end

      if asset.present? && asset != X402::Asset::DEFINITIONS[[x402_connection.asset, network]]&.address
        errors.add(:asset, :not_connection_asset)
      end
    end
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
#  settled_by            :enum             default("lago"), not null
#  status                :enum             default("pending"), not null
#  transaction_hash      :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  customer_id           :uuid
#  invoice_id            :uuid
#  organization_id       :uuid             not null
#  payment_id            :uuid
#  subscription_id       :uuid
#  wallet_transaction_id :uuid
#  x402_connection_id    :uuid             not null
#
# Indexes
#
#  index_x402_settlements_on_customer_id                    (customer_id)
#  index_x402_settlements_on_invoice_id                     (invoice_id)
#  index_x402_settlements_on_network_and_transaction_hash   (network,transaction_hash) UNIQUE WHERE (transaction_hash IS NOT NULL)
#  index_x402_settlements_on_organization_id                (organization_id)
#  index_x402_settlements_on_payment_digest                 (payment_digest) UNIQUE WHERE (status = ANY (ARRAY['pending'::x402_settlement_status, 'settled'::x402_settlement_status]))
#  index_x402_settlements_on_payment_id                     (payment_id) UNIQUE WHERE (payment_id IS NOT NULL)
#  index_x402_settlements_on_pending_credit_purchase_payer  (organization_id,payer_address) UNIQUE WHERE ((kind = 'credit_purchase'::x402_settlement_kind) AND (status = 'pending'::x402_settlement_status))
#  index_x402_settlements_on_pending_invoice_id             (invoice_id) UNIQUE WHERE (status = 'pending'::x402_settlement_status)
#  index_x402_settlements_on_pending_reconcile_after        (reconcile_after) WHERE (status = 'pending'::x402_settlement_status)
#  index_x402_settlements_on_x402_connection_id             (x402_connection_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (payment_id => payments.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#  fk_rails_...  (wallet_transaction_id => wallet_transactions.id)
#  fk_rails_...  (x402_connection_id => x402_connections.id)
#
