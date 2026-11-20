# frozen_string_literal: true

module V2
  class AlertThresholdSerializer < ModelSerializer
    def serialize
      {
        code: model.code,
        value: model.value,
        recurring: model.recurring,
        notify_on: model.notify_on
      }
    end
  end
end
