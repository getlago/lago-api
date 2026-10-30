# frozen_string_literal: true

require "rails_helper"

RSpec.describe "config/cable.yml" do # rubocop:disable RSpec/DescribeClass
  subject(:config) { Rails.application.config_for(Rails.root.join("config/cable.yml"), env: "production") }

  around do |example|
    env_keys = %w[REDIS_URL REDIS_PASSWORD LAGO_REDIS_CABLE_URL LAGO_REDIS_CABLE_PASSWORD]
    original_env = ENV.to_h.slice(*env_keys)
    env_keys.each { |key| ENV.delete(key) }
    example.run
    ENV.update(original_env)
    ENV.delete_if { |k, _| env_keys.include?(k) && !original_env.key?(k) }
  end

  before { ENV["REDIS_URL"] = "rediss://sidekiq:6379" }

  context "with a password for the Redis" do
    # Characters that would break a YAML scalar if the password were written as is.
    before { ENV["REDIS_PASSWORD"] = "p@ss: #word'\"" }

    it "gives ActionCable the URL and the password" do
      expect(config).to eq(adapter: "redis", url: "rediss://sidekiq:6379", channel_prefix: "lago_production", password: "p@ss: #word'\"")
    end
  end

  context "without a password" do
    it "leaves the password out" do
      expect(config).to eq(adapter: "redis", url: "rediss://sidekiq:6379", channel_prefix: "lago_production")
    end
  end
end
