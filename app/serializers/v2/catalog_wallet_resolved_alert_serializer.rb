# frozen_string_literal: true

module V2
  class CatalogWalletResolvedAlertSerializer < CatalogWalletAlertHistorySerializer
    timestamps :resolved_at

    private

    def event_payload
      {
        recovered_thresholds: model.crossed_thresholds,
        in_alarm_thresholds: model.in_alarm_thresholds,
        fully_resolved: model.fully_resolved,
        reason: model.resolution_reason
      }
    end

    # A resolution is recorded at its row's triggered_at
    def resolved_at
      model.triggered_at
    end
  end
end
