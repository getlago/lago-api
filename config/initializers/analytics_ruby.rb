class SegmentError < StandardError
  attr_reader :status, :error_message, :message

  def initialize(status, error_message)
    @status = status
    @error_message = error_message
    @message = "Status: #{status}, Message: #{error_message}"
  end
end

SEGMENT_CLIENT = Segment::Analytics.new({
  write_key: ENV['SEGMENT_WRITE_KEY'],
  on_error: proc { |status, msg| Sentry.capture_exception(SegmentError.new(status, msg)) },
  stub: Rails.env.development? || Rails.env.test?
})
