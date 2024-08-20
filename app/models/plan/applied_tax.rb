# frozen_string_literal: true

class Plan
  class AppliedTax < ApplicationRecord
    self.table_name = 'plans_taxes'

    include PaperTrailTraceable

    belongs_to :plan
    belongs_to :tax
  end
end

# == Schema Information
#
# Table name: plans_taxes
#
#  id         :uuid             not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  plan_id    :uuid             not null
#  tax_id     :uuid             not null
#
# Indexes
#
#  index_plans_taxes_on_plan_id             (plan_id)
#  index_plans_taxes_on_plan_id_and_tax_id  (plan_id,tax_id) UNIQUE
#  index_plans_taxes_on_tax_id              (tax_id)
#
# Foreign Keys
#
#  fk_rails_...  (plan_id => plans.id)
#  fk_rails_...  (tax_id => taxes.id)
#
