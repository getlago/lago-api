# frozen_string_literal: true

module Types
  module Coupons
    class LimitationInput < BaseInputObject
      graphql_name 'LimitationInput'

      argument :plan_ids, [ID], required: false
    end
  end
end
