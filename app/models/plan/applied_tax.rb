# frozen_string_literal: true

class Plan
  class AppliedTax < ApplicationRecord
    self.table_name = "plans_taxes"

    include PaperTrailTraceable

    belongs_to :plan, optional: true
    belongs_to :catalog_plan, optional: true
    belongs_to :tax
    belongs_to :organization

    validate :exactly_one_plan

    private

    # A tax applies to exactly one plan, legacy or catalog.
    def exactly_one_plan
      has_plan = plan_id.present? || plan.present?
      has_catalog_plan = catalog_plan_id.present? || catalog_plan.present?
      return if has_plan ^ has_catalog_plan

      errors.add(:base, :exactly_one_plan_required)
    end
  end
end

# == Schema Information
#
# Table name: plans_taxes
# Database name: primary
#
#  id              :uuid             not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  catalog_plan_id :uuid
#  organization_id :uuid             not null
#  plan_id         :uuid
#  tax_id          :uuid             not null
#
# Indexes
#
#  index_plans_taxes_on_catalog_plan_id_and_tax_id  (catalog_plan_id,tax_id) UNIQUE
#  index_plans_taxes_on_organization_id             (organization_id)
#  index_plans_taxes_on_plan_id                     (plan_id)
#  index_plans_taxes_on_plan_id_and_tax_id          (plan_id,tax_id) UNIQUE
#  index_plans_taxes_on_tax_id                      (tax_id)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_plan_id => catalog_plans.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#  fk_rails_...  (tax_id => taxes.id)
#
