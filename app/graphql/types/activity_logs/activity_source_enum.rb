# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module ActivityLogs
    class ActivitySourceEnum < Types::BaseEnum
      description "Activity Logs source enums"

      [:api, :front, :system].each do |source|
        value source
      end
    end
  end
end
