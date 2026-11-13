# frozen_string_literal: true

class CatalogWallet < ApplicationRecord
  include CatalogWalletSettings

  attr_readonly :currency, :tax_application

  belongs_to :contract
  belongs_to :customer, -> { with_discarded }

  has_many :credit_allocations, class_name: "CatalogWalletCreditAllocation"

  validates :code, uniqueness: {scope: :contract_id, conditions: -> { where(deleted_at: nil) }}
end

# == Schema Information
#
# Table name: catalog_wallets
# Database name: primary
#
#  id                           :uuid             not null, primary key
#  balance_cents                :bigint           default(0), not null
#  code                         :string           not null
#  currency                     :string           not null
#  deleted_at                   :datetime
#  invoice_display_name         :string
#  last_ongoing_balance_sync_at :datetime
#  name                         :string
#  ongoing_balance_cents        :bigint           default(0), not null
#  priority                     :integer          default(50), not null
#  tax_application              :enum             default("tax_on_consumption"), not null
#  terminated_at                :datetime
#  top_up_max_amount_cents      :bigint
#  top_up_min_amount_cents      :bigint
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  contract_id                  :uuid             not null
#  customer_id                  :uuid             not null
#  organization_id              :uuid             not null
#
# Indexes
#
#  index_catalog_wallets_on_contract_id_and_code  (contract_id,code) UNIQUE WHERE (deleted_at IS NULL)
#  index_catalog_wallets_on_customer_id           (customer_id)
#  index_catalog_wallets_on_organization_id       (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#
