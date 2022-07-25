require 'segment/analytics'

if ENV['SEGMENT_WRITE_KEY'] && ENV['LAGO_DISABLE_SEGMENT'] != 'true'
  Analytics = Segment::Analytics.new({
    write_key: ENV['SEGMENT_WRITE_KEY'],
    on_error: Proc.new { |status, msg| print msg }
  })
end
