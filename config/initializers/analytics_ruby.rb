# frozen_string_literal: true

unless ENV['LAGO_DISABLE_SEGMENT'] == 'true'
  class SegmentError < StandardError
    attr_reader :status, :error_message, :message

    def initialize(status, error_message)
      @status = status
      @error_message = error_message
      @message = "Status: #{status}, Message: #{error_message}"

      super
    end
  end

  Segment::Analytics::Logging.logger = Logger.new(nil)

  SEGMENT_CLIENT = Segment::Analytics.new(
    {
      write_key: ENV['SEGMENT_WRITE_KEY'] || "secret_segment_key",
      on_error: proc { |status, msg| Sentry.capture_exception(SegmentError.new(status, msg)) },
      stub: Rails.env.development? || Rails.env.test?,
    },
  )
end
