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
    missing.reject! { |_, path| path.match?(%r{\A/credit_notes/[^/]+/download\z}) }

    expect(missing).to be_empty
  end

  it "routes plan-nested legacy paths to v1 controllers despite the greedy v2 plan code" do
    recognized = Rails.application.routes.recognize_path("/api/v2/plans/foo/charges", method: :get)

    expect(recognized[:controller]).to eq("api/v1/plans/charges")
    expect(recognized[:plan_code]).to eq("foo")
  end

  it "keeps customer-nested paths on their shared controllers" do
    recognized = Rails.application.routes.recognize_path("/api/v2/customers/customer/credit_notes", method: :get)

    expect(recognized[:controller]).to eq("api/v2/customers/credit_notes")
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

  it "routes billable metric CRUD to v2 without changing v1" do
    {
      get: %w[/billable_metrics /billable_metrics/api.requests],
      post: %w[/billable_metrics],
      put: %w[/billable_metrics/api.requests],
      patch: %w[/billable_metrics/api.requests],
      delete: %w[/billable_metrics/api.requests]
    }.each do |method, paths|
      paths.each do |path|
        recognized = Rails.application.routes.recognize_path("/api/v2#{path}", method:)
        expect(recognized[:controller]).to eq("api/v2/billable_metrics")
        expect(recognized[:code]).to eq("api.requests") if path.end_with?("api.requests")
        expect(Rails.application.routes.recognize_path("/api/v1#{path}", method:)[:controller]).to eq("api/v1/billable_metrics")
      end
    end
  end

  it "does not route billable metric expression evaluation to v1 under v2" do
    path = "/billable_metrics/evaluate_expression"
    expect(Rails.application.routes.recognize_path("/api/v2#{path}", method: :post))
      .to include(controller: "api/unknown_v2_routes", action: "show")
    expect(Rails.application.routes.recognize_path("/api/v1#{path}", method: :post))
      .to include(controller: "api/v1/billable_metrics", action: "evaluate_expression")
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

  it "routes credit note actions to v2 while preserving the v1 controller" do
    id = SecureRandom.uuid
    paths = {
      get: ["/api/v2/credit_notes", "/api/v2/credit_notes/#{id}"],
      post: ["/api/v2/credit_notes", "/api/v2/credit_notes/estimate", "/api/v2/credit_notes/#{id}/download_pdf", "/api/v2/credit_notes/#{id}/download_xml", "/api/v2/credit_notes/#{id}/resend_email"],
      put: ["/api/v2/credit_notes/#{id}", "/api/v2/credit_notes/#{id}/void"],
      patch: ["/api/v2/credit_notes/#{id}"]
    }

    paths.each do |method, urls|
      urls.each do |url|
        expect(Rails.application.routes.recognize_path(url, method:)[:controller]).to eq("api/v2/credit_notes")
      end
    end

    expect(Rails.application.routes.recognize_path("/api/v1/credit_notes", method: :get)[:controller]).to eq("api/v1/credit_notes")
  end

  it "routes credit-note metadata actions to v2 and keeps unsupported actions out of v1 fallback" do
    id = SecureRandom.uuid

    [
      [:post, "/api/v2/credit_notes/#{id}/metadata"],
      [:patch, "/api/v2/credit_notes/#{id}/metadata"],
      [:delete, "/api/v2/credit_notes/#{id}/metadata"],
      [:delete, "/api/v2/credit_notes/#{id}/metadata/key"]
    ].each do |method, path|
      recognized = Rails.application.routes.recognize_path(path, method:)
      expect(recognized[:controller]).to eq("api/v2/credit_notes/metadata")
    end

    unsupported = Rails.application.routes.recognize_path("/api/v2/credit_notes/#{id}/download", method: :post)
    expect(unsupported.slice(:controller, :action)).to eq(controller: "api/unknown_v2_routes", action: "show")
    expect(Rails.application.routes.recognize_path("/api/v1/credit_notes/#{id}/download", method: :post)[:controller])
      .to eq("api/v1/credit_notes")

    beta_fallback = Rails.application.routes.recognize_path("/api/v2/add_ons", method: :get)
    expect(beta_fallback[:controller]).to eq("api/v1/add_ons")
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

  it "routes top-level payment endpoints to v2 without changing v1" do
    {
      get: ["/payments", "/payments/#{SecureRandom.uuid}"],
      post: ["/payments"]
    }.each do |method, paths|
      paths.each do |path|
        expect(Rails.application.routes.recognize_path("/api/v2#{path}", method:)[:controller]).to eq("api/v2/payments")
        expect(Rails.application.routes.recognize_path("/api/v1#{path}", method:)[:controller]).to eq("api/v1/payments")
      end
    end
  end

  it "routes top-level payment request endpoints to v2 without changing v1" do
    {
      get: ["/payment_requests", "/payment_requests/#{SecureRandom.uuid}"],
      post: ["/payment_requests"]
    }.each do |method, paths|
      paths.each do |path|
        expect(Rails.application.routes.recognize_path("/api/v2#{path}", method:)[:controller]).to eq("api/v2/payment_requests")
        expect(Rails.application.routes.recognize_path("/api/v1#{path}", method:)[:controller]).to eq("api/v1/payment_requests")
      end
    end
  end

  it "routes customer payment endpoints to their controllers" do
    {
      [:get, "/api/v2/customers/cus_1/payments"] => "api/v2/customers/payments",
      [:get, "/api/v2/customers/cus_1/payment_requests"] => "api/v2/customers/payment_requests",
      [:post, "/api/v2/customers/cus_1/checkout_url"] => "api/v2/customers/checkout_urls",
      [:get, "/api/v2/customers/cus_1/payment_methods"] => "api/v2/customers/payment_methods",
      [:delete, "/api/v2/customers/cus_1/payment_methods/pm_1"] => "api/v2/customers/payment_methods",
      [:put, "/api/v2/customers/cus_1/payment_methods/pm_1/set_as_default"] => "api/v2/customers/payment_methods"
    }.each do |(method, path), controller|
      expect(Rails.application.routes.recognize_path(path, method:)[:controller]).to eq(controller)
    end
  end

  it "routes payment receipt endpoints to the v2 controller" do
    id = SecureRandom.uuid

    {
      get: ["/api/v2/payment_receipts", "/api/v2/payment_receipts/#{id}"],
      post: ["/api/v2/payment_receipts/#{id}/resend_email"]
    }.each do |method, paths|
      paths.each do |path|
        expect(Rails.application.routes.recognize_path(path, method:)[:controller]).to eq("api/v2/payment_receipts")
      end
    end
  end

  it "routes webhook endpoint endpoints to the v2 controller" do
    id = SecureRandom.uuid

    {
      get: ["/api/v2/webhook_endpoints", "/api/v2/webhook_endpoints/#{id}"],
      post: ["/api/v2/webhook_endpoints"],
      put: ["/api/v2/webhook_endpoints/#{id}"],
      patch: ["/api/v2/webhook_endpoints/#{id}"],
      delete: ["/api/v2/webhook_endpoints/#{id}"]
    }.each do |method, paths|
      paths.each do |path|
        expect(Rails.application.routes.recognize_path(path, method:)[:controller]).to eq("api/v2/webhook_endpoints")
      end
    end
  end
end
