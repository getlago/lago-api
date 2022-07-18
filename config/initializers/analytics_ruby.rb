# frozen_string_literal: true

if ENV['SEGMENT_WRITE_KEY']
  Analytics = Segment::Analytics.new({
    write_key: ENV['SEGMENT_WRITE_KEY'],
    on_error: Proc.new { |status, msg| print msg }
  })
end

# Questions
# 1.
# current_user and current_organization are not available in services
# Have to use result.user.memberships.first.id and result.user.organizations.first.id
# 2.
# Cannot find a place to track organization created
