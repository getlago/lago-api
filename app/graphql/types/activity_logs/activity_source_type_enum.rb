# frozen_string_literal: true

module Types
  module ActivityLogs
    class ActivitySourceTypeEnum < Types::BaseEnum
      description "Activity Logs source type enums"

      [:api, :front, :system].each do |type|
        value type
      end
    end
  end
end
