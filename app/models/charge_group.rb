# frozen_string_literal: true

class ChargeGroup < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :plan, -> { with_discarded }, touch: true

  has_many :charges
  has_many :usage_charge_groups
end
