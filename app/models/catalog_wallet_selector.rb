# frozen_string_literal: true

class CatalogWalletSelector < ApplicationRecord
  SELECTOR_TYPES = {
    fee_type: "fee_type",
    product_category: "product_category",
    product: "product",
    product_filters: "product_filters"
  }.freeze

  FEE_TYPES = {
    fixed: "fixed",
    metered: "metered"
  }.freeze

  belongs_to :organization
  belongs_to :plan_wallet, -> { with_discarded }, optional: true
  belongs_to :catalog_wallet, -> { with_discarded }, optional: true
  belongs_to :product_category, -> { with_discarded }, optional: true
  belongs_to :product, -> { with_discarded }, optional: true
  belongs_to :product_filter, -> { with_discarded }, optional: true

  enum :selector_type, SELECTOR_TYPES, validate: true, prefix: true
  enum :fee_type, FEE_TYPES, validate: {allow_nil: true}, prefix: true

  validates_with ParentPresenceValidator, parents: %i[plan_wallet catalog_wallet], error: :exactly_one_owner_required
end

# == Schema Information
#
# Table name: catalog_wallet_selectors
# Database name: primary
#
#  id                   :uuid             not null, primary key
#  fee_type             :enum
#  selector_type        :enum             not null
#  with_product_filters :boolean          default(FALSE), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  catalog_wallet_id    :uuid
#  organization_id      :uuid             not null
#  plan_wallet_id       :uuid
#  product_category_id  :uuid
#  product_filter_id    :uuid
#  product_id           :uuid
#
# Indexes
#
#  index_catalog_wallet_selectors_on_catalog_wallet_and_target  (catalog_wallet_id,selector_type,fee_type,product_category_id,product_id,product_filter_id) UNIQUE NULLS NOT DISTINCT WHERE (catalog_wallet_id IS NOT NULL)
#  index_catalog_wallet_selectors_on_organization_id            (organization_id)
#  index_catalog_wallet_selectors_on_plan_wallet_and_target     (plan_wallet_id,selector_type,fee_type,product_category_id,product_id,product_filter_id) UNIQUE NULLS NOT DISTINCT WHERE (plan_wallet_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_wallet_id => catalog_wallets.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_wallet_id => plan_wallets.id)
#  fk_rails_...  (product_category_id => product_categories.id)
#  fk_rails_...  (product_filter_id => product_filters.id)
#  fk_rails_...  (product_id => products.id)
#
