# frozen_string_literal: true

class PricingUnit < ApplicationRecord
  belongs_to :organization

  validates :name, :code, :short_name, presence: true
  validates :code, uniqueness: {scope: :organization_id}
  validates :description, length: {maximum: 600}, allow_nil: true

  def exponent
    2
  end

  def subunit_to_unit
    10**exponent
  end
end

# == Schema Information
#
# Table name: pricing_units
#
#  id              :uuid             not null, primary key
#  code            :string
#  description     :string
#  name            :string
#  short_name      :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_pricing_units_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
