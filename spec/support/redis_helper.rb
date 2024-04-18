# frozen_string_literal: true

require 'mock_redis'
require 'redis'

RSpec.configure do |config|
  config.before(:each, type: :with_redis) do
    mock_redis = MockRedis.new
    allow(Redis).to receive(:new).and_return(mock_redis)
  end
end
