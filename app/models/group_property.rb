# frozen_string_literal: true

class GroupProperty < ApplicationRecord
  belongs_to :charge
  belongs_to :group

  validates :values, presence: true
end
