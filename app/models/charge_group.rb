# frozen_string_literal: true

class ChargeGroup < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  has_many :charges
  has_many :usage_charge_groups
end
