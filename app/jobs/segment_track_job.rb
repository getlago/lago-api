class SegmentTrackJob < ApplicationJob
  queue_as :default

  def perform(membership_id:, event:, properties:)
    SEGMENT_CLIENT.track(
      user_id: membership_id,
      event: event,
      properties: properties.merge(hosting_type, version)
    )
  end

  private

  def hosting_type
    { hosting_type: ENV['LAGO_CLOUD'] == 'true' ? 'cloud' : 'self' }
  end

  def version
    { version: Utils::VersionService.new.version.version.number }
  end
end
