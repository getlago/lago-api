# frozen_string_literal: true

# The product-catalog plan: a named, priced envelope whose pricing lives in
# its attached rate cards, not in legacy plan columns. It is the v2 catalog's
# own table — the legacy `plans` table is untouched and never shared.
class CatalogPlan < ApplicationRecord
  include PaperTrailTraceable
  include Currencies
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization

  validates :name, presence: true
  validates :code, presence: true
  validates :currency, inclusion: {in: currency_list}

  default_scope -> { kept }
end

# == Schema Information
#
# Table name: catalog_plans
# Database name: primary
#
#  id                   :uuid             not null, primary key
#  code                 :string           not null
#  currency             :string           not null
#  deleted_at           :datetime
#  description          :string
#  invoice_display_name :string
#  name                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  organization_id      :uuid             not null
#
# Indexes
#
#  index_catalog_plans_on_deleted_at                (deleted_at)
#  index_catalog_plans_on_organization_id           (organization_id)
#  index_catalog_plans_on_organization_id_and_code  (organization_id,code) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
