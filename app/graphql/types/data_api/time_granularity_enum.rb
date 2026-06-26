# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module DataApi
    class TimeGranularityEnum < Types::BaseEnum
      value :daily
      value :weekly
      value :monthly
    end
  end
end
