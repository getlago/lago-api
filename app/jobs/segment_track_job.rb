class SegmentTrackJob < ApplicationJob
  queue_as :default

  def perform(event:, properties:)
    SEGMENT_CLIENT.track(
      user_id: CurrentContext.membership,
      event: event,
      properties: properties.merge(hosting_type, version)
    )
  end

  private

  def hosting_type
    { hosting_type: ENV['HOSTING_TYPE'] }
  end

  def version
    { version: Utils::VersionService.new.version.version.number }
  end
end
