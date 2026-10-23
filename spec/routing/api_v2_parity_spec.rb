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

  it "routes plan-nested legacy paths to v1 controllers despite the greedy v2 plan code" do
    recognized = Rails.application.routes.recognize_path("/api/v2/plans/foo/charges", method: :get)

    expect(recognized[:controller]).to eq("api/v1/plans/charges")
    expect(recognized[:plan_code]).to eq("foo")
  end

  it "keeps customer-nested paths on their shared controllers" do
    recognized = Rails.application.routes.recognize_path("/api/v2/customers/customer/invoices", method: :get)

    expect(recognized[:controller]).to eq("api/v1/customers/invoices")
    expect(recognized[:customer_external_id]).to eq("customer")
  end

  it "routes customer CRUD to v2 without changing v1" do
    {
      get: %w[/customers /customers/customer.eu],
      post: %w[/customers],
      put: %w[/customers/customer.eu],
      patch: %w[/customers/customer.eu],
      delete: %w[/customers/customer.eu]
    }.each do |method, paths|
      paths.each do |path|
        recognized = Rails.application.routes.recognize_path("/api/v2#{path}", method:)

        expect(recognized[:controller]).to eq("api/v2/customers")
      end
    end

    expect(Rails.application.routes.recognize_path("/api/v1/customers", method: :post)[:controller]).to eq("api/v1/customers")
  end

  it "routes billing entity endpoints to v2 without changing v1" do
    {
      get: %w[/billing_entities /billing_entities/entity.eu],
      post: %w[/billing_entities],
      put: %w[/billing_entities/entity.eu],
      patch: %w[/billing_entities/entity.eu]
    }.each do |method, paths|
      paths.each do |path|
        expect(Rails.application.routes.recognize_path("/api/v2#{path}", method:)[:controller]).to eq("api/v2/billing_entities")
      end
    end

    expect(Rails.application.routes.recognize_path("/api/v1/billing_entities", method: :post)[:controller]).to eq("api/v1/billing_entities")
  end

  it "routes tax endpoints to the v2 controller" do
    {
      get: %w[/api/v2/taxes /api/v2/taxes/vat.eu],
      post: %w[/api/v2/taxes],
      put: %w[/api/v2/taxes/vat.eu],
      patch: %w[/api/v2/taxes/vat.eu],
      delete: %w[/api/v2/taxes/vat.eu]
    }.each do |method, paths|
      paths.each do |path|
        recognized = Rails.application.routes.recognize_path(path, method:)

        expect(recognized[:controller]).to eq("api/v2/taxes")
      end
    end
  end

  it "routes fee endpoints to the v2 controller" do
    id = SecureRandom.uuid

    {
      get: ["/api/v2/fees", "/api/v2/fees/#{id}"],
      put: ["/api/v2/fees/#{id}"],
      patch: ["/api/v2/fees/#{id}"],
      delete: ["/api/v2/fees/#{id}"]
    }.each do |method, paths|
      paths.each do |path|
        expect(Rails.application.routes.recognize_path(path, method:)[:controller]).to eq("api/v2/fees")
      end
    end
  end
end
