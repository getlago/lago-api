# frozen_string_literal: true

module Types
  module Analytics
    class TimeGranularityEnum < Types::BaseEnum
      value :daily
      value :weekly
      value :monthly
    end
  end
end
