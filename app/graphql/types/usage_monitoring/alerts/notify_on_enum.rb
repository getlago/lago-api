# frozen_string_literal: true

module Types
  module UsageMonitoring
    module Alerts
      class NotifyOnEnum < Types::BaseEnum
        ::UsageMonitoring::AlertThreshold::NOTIFY_ON_VALUES.each do |transition|
          value transition
        end
      end
    end
  end
end
