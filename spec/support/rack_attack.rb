# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each, rack_attack: true) do
    Rack::Attack.enabled = true
    Rack::Attack.reset!
  end

  config.after(:each, rack_attack: true) do
    Rack::Attack.enabled = false
  end
end

Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
