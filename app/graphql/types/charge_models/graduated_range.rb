# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module ChargeModels
    class GraduatedRange < Types::BaseObject
      field :from_value, Float, null: false
      field :to_value, Float, null: true

      field :flat_amount, String, null: false
      field :per_unit_amount, String, null: false
    end
  end
end
