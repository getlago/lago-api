# frozen_string_literal: true

class CatalogWalletConsumption < ApplicationRecord
  belongs_to :organization
  belongs_to :outbound_transaction, class_name: "CatalogWalletTransaction", inverse_of: :fundings
  belongs_to :inbound_transaction, class_name: "CatalogWalletTransaction", inverse_of: :consumptions
  belongs_to :fee, optional: true

  validates :credit_amount_cents, numericality: {only_integer: true, greater_than: 0}
  validate :inbound_transaction_must_be_inbound
  validate :outbound_transaction_must_be_outbound

  private

  def inbound_transaction_must_be_inbound
    return if inbound_transaction.nil?
    return if inbound_transaction.inbound?

    errors.add(:inbound_transaction, :invalid)
  end

  def outbound_transaction_must_be_outbound
    return if outbound_transaction.nil?
    return if outbound_transaction.outbound?

    errors.add(:outbound_transaction, :invalid)
  end
end

# == Schema Information
#
# Table name: catalog_wallet_consumptions
# Database name: primary
#
#  id                      :uuid             not null, primary key
#  credit_amount_cents     :bigint           not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  fee_id                  :uuid
#  inbound_transaction_id  :uuid             not null
#  organization_id         :uuid             not null
#  outbound_transaction_id :uuid             not null
#
# Indexes
#
#  index_catalog_wallet_consumptions_on_fee_id                    (fee_id) WHERE (fee_id IS NOT NULL)
#  index_catalog_wallet_consumptions_on_inbound_transaction_id    (inbound_transaction_id)
#  index_catalog_wallet_consumptions_on_organization_id           (organization_id)
#  index_catalog_wallet_consumptions_on_outbound_inbound_and_fee  (outbound_transaction_id,inbound_transaction_id,fee_id) UNIQUE NULLS NOT DISTINCT
#
# Foreign Keys
#
#  fk_rails_...  (fee_id => fees.id)
#  fk_rails_...  (inbound_transaction_id => catalog_wallet_transactions.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (outbound_transaction_id => catalog_wallet_transactions.id)
#
