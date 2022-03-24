# frozen_string_literal: true

class Charge < ApplicationRecord
  belongs_to :plan
  belongs_to :billable_metric
end
