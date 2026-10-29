# frozen_string_literal: true

module Utils
  class SegmentTrack
    class << self
      def refund_status_changed(status, credit_note_id, organization_id)
        SegmentTrackJob.perform_later(
          membership_id: CurrentContext.membership,
          event: "refund_status_changed",
          properties: {
            organization_id: organization_id,
            credit_note_id: credit_note_id,
            refund_status: status
          }
        )
      end
    end
  end
end
