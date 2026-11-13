# frozen_string_literal: true

class PlanWallet < ApplicationRecord
  include CatalogWalletSettings

  belongs_to :catalog_plan, -> { with_discarded }

  has_many :credit_allocations, class_name: "PlanWalletCreditAllocation"

  validates :code, uniqueness: {scope: :catalog_plan_id, conditions: -> { where(deleted_at: nil) }}
end

# == Schema Information
#
# Table name: plan_wallets
# Database name: primary
#
#  id                      :uuid             not null, primary key
#  code                    :string           not null
#  currency                :string           not null
#  deleted_at              :datetime
#  invoice_display_name    :string
#  name                    :string
#  priority                :integer          default(50), not null
#  tax_application         :enum             default("tax_on_consumption"), not null
#  top_up_max_amount_cents :bigint
#  top_up_min_amount_cents :bigint
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  catalog_plan_id         :uuid             not null
#  organization_id         :uuid             not null
#
# Indexes
#
#  index_plan_wallets_on_catalog_plan_id_and_code  (catalog_plan_id,code) UNIQUE WHERE (deleted_at IS NULL)
#  index_plan_wallets_on_organization_id           (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_plan_id => catalog_plans.id)
#  fk_rails_...  (organization_id => organizations.id)
#
