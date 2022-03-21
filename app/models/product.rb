# frozen_string_literal: true

class Product < ApplicationRecord
  belongs_to :organization

  has_many :product_items, dependent: :destroy
  has_many :billable_metrics, through: :product_items

  validates :name, presence: true
end
