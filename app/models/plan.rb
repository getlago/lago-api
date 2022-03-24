# frozen_string_literal: true

class Plan < ApplicationRecord
  belongs_to :organization

  has_many :charges, dependent: :destroy
  has_many :billable_metrics, through: :charges

  validates :name, presence: true
end
