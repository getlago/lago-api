# frozen_string_literal: true

require 'flipper/adapters/redis'

Flipper.configure do |config|
  config.adapter { Flipper::Adapters::Redis.new(Redis.new(db: 8)) }
end
