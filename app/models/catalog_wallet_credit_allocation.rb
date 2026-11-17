# frozen_string_literal: true

class CatalogWalletCreditAllocation < ApplicationRecord
  include CreditAllocationRule

  belongs_to :catalog_wallet, -> { with_discarded }

  has_many :transactions, class_name: "CatalogWalletTransaction", foreign_key: :credit_allocation_id, inverse_of: :credit_allocation

  validates :code, uniqueness: {scope: :catalog_wallet_id, conditions: -> { where(deleted_at: nil) }}
end

# == Schema Information
#
# Table name: catalog_wallet_credit_allocations
# Database name: primary
#
#  id                                  :uuid             not null, primary key
#  billing_cycles                      :integer
#  code                                :string           not null
#  credit_amount_cents                 :bigint           not null
#  deleted_at                          :datetime
#  invoice_requires_successful_payment :boolean
#  priority                            :integer          default(50), not null
#  purchase_amount_cents               :bigint
#  threshold_amount_cents              :bigint
#  trigger                             :enum             not null
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  catalog_wallet_id                   :uuid             not null
#  organization_id                     :uuid             not null
#  product_filter_id                   :uuid
#  product_id                          :uuid
#
# Indexes
#
#  index_catalog_wallet_credit_allocations_on_organization_id   (organization_id)
#  index_catalog_wallet_credit_allocations_on_wallet_and_code   (catalog_wallet_id,code) UNIQUE WHERE (deleted_at IS NULL)
#  index_catalog_wallet_credit_allocations_one_ongoing_balance  (catalog_wallet_id) UNIQUE WHERE ((trigger = 'ongoing_balance'::catalog_wallet_credit_allocation_trigger) AND (deleted_at IS NULL))
#
# Foreign Keys
#
#  fk_rails_...  (catalog_wallet_id => catalog_wallets.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_filter_id => product_filters.id)
#  fk_rails_...  (product_id => products.id)
#
