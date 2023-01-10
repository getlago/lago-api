# frozen_string_literal: true

ActiveJob::Uniqueness.configure do |config|
  config.lock_ttl = 1.hour
end
