# frozen_string_literal: true

module Types
  module UsageMonitoring
    module Alerts
      class ThresholdInput < BaseInputObject
        argument :code, String, required: false
        argument :notify_on, [NotifyOnEnum], required: false,
          description: "Transitions this threshold notifies on. Must include triggered. Adding resolved requires a code that is unique within the alert, and is not supported on recurring thresholds."
        argument :recurring, Boolean, required: false
        argument :value, String, required: true
      end
    end
  end
end
