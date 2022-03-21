# frozen_string_literal: true

class Product < ApplicationRecord
  belongs_to :organization

  validates :name, presence: true
end
