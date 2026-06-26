# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Plans
    class IntervalEnum < Types::BaseEnum
      graphql_name "PlanInterval"

      Plan::INTERVALS.each do |type|
        value type
      end
    end
  end
end
