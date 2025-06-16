# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::OrganizationsController, type: [:request, :admin] do
  let(:organization) { create(:organization) }

  describe "POST /admin/organizations" do
    let(:create_params) do
      {
        name: "New Organization",
        email: "contact@neworg.com",
        country: "US",
        address_line1: "123 Main St",
        city: "San Francisco",
        state: "CA",
        zipcode: "94105",
        timezone: "America/Los_Angeles",
        premium_features: true
      }
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_ADMIN_API_KEY").and_return("admin-secret-key")
    end

    it "creates a new organization with premium features" do
      admin_post(
        "/admin/organizations",
        create_params,
        api_key: true
      )

      expect(response).to have_http_status(:created)

      aggregate_failures do
        expect(json[:organization][:name]).to eq("New Organization")
        expect(json[:organization][:email]).to eq("contact@neworg.com")
        expect(json[:organization][:country]).to eq("US")
        expect(json[:organization][:timezone]).to eq("America/Los_Angeles")
        expect(json[:organization][:premium_features]).to be true
        
        # Verify organization was created in database
        org = Organization.find_by(name: "New Organization")
        expect(org).to be_present
        expect(org.premium_features).to be true
        expect(org.api_keys.count).to eq(1)
      end
    end

    it "creates a new organization without premium features" do
      admin_post(
        "/admin/organizations",
        create_params.merge(premium_features: false),
        api_key: true
      )

      expect(response).to have_http_status(:created)
      expect(json[:organization][:premium_features]).to be false
    end

    it "returns validation errors for invalid params" do
      admin_post(
        "/admin/organizations",
        { name: "" },
        api_key: true
      )

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json[:error][:message]).to be_present
    end

    it "returns unauthorized without valid API key" do
      allow(ENV).to receive(:[]).with("LAGO_ADMIN_API_KEY").and_return("different-key")
      
      admin_post(
        "/admin/organizations",
        create_params,
        api_key: true
      )

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PUT /admin/organizations/:id" do
    let(:update_params) do
      {
        name: "FooBar"
      }
    end

    it "updates an organization" do
      admin_put(
        "/admin/organizations/#{organization.id}",
        update_params
      )

      expect(response).to have_http_status(:success)

      aggregate_failures do
        expect(json[:organization][:name]).to eq("FooBar")
        expect(organization.reload.name).to eq("FooBar")
      end
    end
  end
end
