class SegmentTrackJob < ApplicationJob
  queue_as :default

  def perform(membership_id:, event:, properties:)
    SEGMENT_CLIENT.track(
      membership_id: membership_id,
      event: event,
      properties: properties
    )
  end
end
