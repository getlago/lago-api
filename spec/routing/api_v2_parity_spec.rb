# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v2 routing parity" do
  def api_routes(version)
    Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.delete_suffix("(.:format)")
      next unless path.start_with?("/api/#{version}/")

      [route.verb, path.sub("/api/#{version}", "")]
    end
  end

  it "exposes every v1 endpoint under v2" do
    missing = api_routes("v1") - api_routes("v2")

    expect(missing).to be_empty
  end

  it "falls back to v1 controllers for shared resources" do
    customers = Rails.application.routes.routes.find do |route|
      route.path.spec.to_s.start_with?("/api/v2/customers(") && route.verb == "GET"
    end

    expect(customers.defaults[:controller]).to eq("api/v1/customers")
  end
end
