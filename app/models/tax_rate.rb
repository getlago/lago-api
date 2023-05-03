# frozen_string_literal: true

class TaxRate < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization

  validates :name, :value, presence: true
  validates :code, presence: true, uniqueness: { scope: :organization_id }
end
