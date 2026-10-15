# frozen_string_literal: true

module Types
  module UsageMonitoring
    module Alerts
      class ThresholdObject < Types::BaseObject
        graphql_name "AlertThreshold"

        field :code, String, null: true
        field :notify_on, [NotifyOnEnum], null: false,
          description: "Transitions this threshold notifies on. Always includes triggered; resolved is opt in."
        field :recurring, Boolean, null: false
        field :value, String, null: false
      end
    end
  end
end
