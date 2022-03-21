# frozen_string_literal: true

class ProductItem < ApplicationRecord
  belongs_to :product
  belongs_to :billable_metric
end
