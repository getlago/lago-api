# frozen_string_literal: true

class CatalogWalletAppliedTax < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization
  belongs_to :plan_wallet, -> { with_discarded }, optional: true
  belongs_to :catalog_wallet, -> { with_discarded }, optional: true
  belongs_to :tax

  validates_with ParentPresenceValidator, parents: %i[plan_wallet catalog_wallet], error: :exactly_one_owner_required
end

# == Schema Information
#
# Table name: catalog_wallet_applied_taxes
# Database name: primary
#
#  id                :uuid             not null, primary key
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  catalog_wallet_id :uuid
#  organization_id   :uuid             not null
#  plan_wallet_id    :uuid
#  tax_id            :uuid             not null
#
# Indexes
#
#  idx_on_catalog_wallet_id_tax_id_95501fdc40             (catalog_wallet_id,tax_id) UNIQUE WHERE (catalog_wallet_id IS NOT NULL)
#  idx_on_plan_wallet_id_tax_id_d82685b30a                (plan_wallet_id,tax_id) UNIQUE WHERE (plan_wallet_id IS NOT NULL)
#  index_catalog_wallet_applied_taxes_on_organization_id  (organization_id)
#  index_catalog_wallet_applied_taxes_on_tax_id           (tax_id)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_wallet_id => catalog_wallets.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_wallet_id => plan_wallets.id)
#  fk_rails_...  (tax_id => taxes.id)
#
