# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::OrganizationActivationsController, type: [:request, :admin] do
  include_context "with self-serve enabled"

  let(:billing_accounts_key) { "billing-accounts-key-used-in-specs-only" }
  let(:self_serve_env) do
    {
      "LAGO_SELF_SERVE_ENABLED" => "true",
      "LAGO_ADMIN_API_BILLING_ACCOUNTS_KEY" => billing_accounts_key,
      "ADMIN_API_KEY" => AdminHelper::ADMIN_API_KEY
    }
  end
  let(:organization) { create(:organization, :self_serve, activation_status: "pending_payment_method") }
  let(:organization_id) { organization.id }
  let(:headers) { {"Authorization" => "Bearer #{billing_accounts_key}"} }

  describe "POST /admin/organizations/:id/activate" do
    subject(:request) { post("/admin/organizations/#{organization_id}/activate", headers:) }

    it "opens the organization" do
      request

      expect(response).to have_http_status(:ok)
      expect(json).to eq(organization: {id: organization.id, activation_status: "active"})
      expect(organization.reload.activation_status).to eq("active")
    end

    context "with an active organization" do
      let(:organization) { create(:organization, :self_serve) }

      it "answers its state without changing anything" do
        request

        expect(response).to have_http_status(:ok)
        expect(json).to eq(organization: {id: organization.id, activation_status: "active"})
      end
    end

    context "with an organization that is not self-serve" do
      let(:organization) { create(:organization) }

      it "refuses" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(status: 403, error: "Forbidden", code: "organization_not_self_serve_production")
      end
    end

    context "with an unknown organization" do
      let(:organization_id) { SecureRandom.uuid }

      it "returns not found" do
        request

        expect(response).to be_not_found_error("organization")
      end
    end

    {
      "a lowercase scheme" => "bearer billing-accounts-key-used-in-specs-only",
      "extra spaces after the scheme" => "Bearer   billing-accounts-key-used-in-specs-only",
      "trailing whitespace" => "Bearer billing-accounts-key-used-in-specs-only  "
    }.each do |description, authorization|
      context "with #{description}" do
        let(:headers) { {"Authorization" => authorization} }

        it "opens the organization" do
          request

          expect(response).to have_http_status(:ok)
          expect(organization.reload.activation_status).to eq("active")
        end
      end
    end

    {
      "ADMIN_API_KEY" => {"Authorization" => "Bearer #{AdminHelper::ADMIN_API_KEY}"},
      "ADMIN_API_KEY in its own header" => {"X-Admin-API-Key" => AdminHelper::ADMIN_API_KEY},
      "a wrong key" => {"Authorization" => "Bearer another-key"},
      "the key without the Bearer scheme" => {"Authorization" => "billing-accounts-key-used-in-specs-only"},
      "no header" => {}
    }.each do |description, wrong_headers|
      context "with #{description}" do
        let(:headers) { wrong_headers }

        it "refuses the request and changes nothing" do
          request

          expect(response).to have_http_status(:unauthorized)
          expect(organization.reload.activation_status).to eq("pending_payment_method")
        end
      end
    end

    context "with self-serve disabled" do
      let(:self_serve_env) { super().merge("LAGO_SELF_SERVE_ENABLED" => "false") }

      it "is not drawn" do
        request

        expect(response).to have_http_status(:not_found)
        expect(organization.reload.activation_status).to eq("pending_payment_method")
      end
    end

    context "without a billing-accounts key" do
      let(:self_serve_env) { super().merge("LAGO_ADMIN_API_BILLING_ACCOUNTS_KEY" => "") }
      let(:headers) { {"Authorization" => "Bearer "} }

      it "is not drawn" do
        request

        expect(response).to have_http_status(:not_found)
        expect(organization.reload.activation_status).to eq("pending_payment_method")
      end
    end
  end

  it "keeps the other admin routes closed to the billing-accounts key" do
    admin_put("/admin/organizations/#{organization.id}", {name: "Renamed"}, admin_headers(billing_accounts_key))

    expect(response).to have_http_status(:unauthorized)
    expect(organization.reload.name).not_to eq("Renamed")
  end

  it "draws only the activation route outside local environments" do
    # config/routes.rb drawn into a route set of its own, so the application's routes stay as they are.
    route_set = ActionDispatch::Routing::RouteSet.new
    route_set.draw_paths = Rails.application.routes.draw_paths
    allow(Rails.application).to receive(:routes).and_return(route_set)
    allow(Rails.env).to receive(:local?).and_return(false)
    load Rails.root.join("config/routes.rb")

    expect(route_set.recognize_path("/admin/organizations/#{organization.id}/activate", method: :post))
      .to include(controller: "admin/organization_activations", action: "create")
    expect(route_set.recognize_path("/admin/organizations/#{organization.id}", method: :put))
      .to include(controller: "application", action: "not_found")
  end
end
