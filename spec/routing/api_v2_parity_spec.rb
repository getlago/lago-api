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
    recognized = Rails.application.routes.recognize_path("/api/v2/customers/customer/credit_notes", method: :get)

    expect(recognized[:controller]).to eq("api/v1/customers/credit_notes")
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

  it "routes organization endpoints to v2 without changing v1" do
    %i[get put].each do |method|
      expect(Rails.application.routes.recognize_path("/api/v2/organizations", method:)[:controller]).to eq("api/v2/organizations")
      expect(Rails.application.routes.recognize_path("/api/v1/organizations", method:)[:controller]).to eq("api/v1/organizations")
    end
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

  it "routes the invoice payment URL to its v2 controller" do
    expect(Rails.application.routes.recognize_path("/api/v2/invoices/#{SecureRandom.uuid}/payment_url", method: :post)[:controller])
      .to eq("api/v2/invoices/payment_urls")
  end

  it "routes catalog invoice endpoints to the v2 controller" do
    id = SecureRandom.uuid

    [
      [:get, "/api/v2/invoices"],
      [:get, "/api/v2/invoices/#{id}"],
      [:post, "/api/v2/invoices/#{id}/void"],
      [:post, "/api/v2/invoices/#{id}/download_pdf"],
      [:post, "/api/v2/invoices/#{id}/resend_email"],
      [:post, "/api/v2/invoices/#{id}/retry_taxes"],
      [:post, "/api/v2/invoices/#{id}/retry_payment"],
      [:put, "/api/v2/invoices/#{id}/refresh"],
      [:put, "/api/v2/invoices/#{id}/finalize"],
      [:put, "/api/v2/invoices/#{id}"],
      [:patch, "/api/v2/invoices/#{id}"],
      [:delete, "/api/v2/invoices/#{id}"],
      [:post, "/api/v2/invoices/#{id}/lose_dispute"]
    ].each do |method, path|
      expect(Rails.application.routes.recognize_path(path, method:)[:controller]).to eq("api/v2/invoices")
    end
  end

  it "routes a customer external id containing a dot, as v2 contracts do" do
    recognized = Rails.application.routes.recognize_path("/api/v2/customers/acme.eu/invoices", method: :get)

    expect(recognized).to include(controller: "api/v2/customers/invoices", customer_external_id: "acme.eu")
  end

  it "routes the customer invoice list to the v2 controller" do
    recognized = Rails.application.routes.recognize_path("/api/v2/customers/cus_1/invoices", method: :get)

    expect(recognized[:controller]).to eq("api/v2/customers/invoices")
  end
end
