# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::OrganizationsController, type: [:request, :admin] do
  let(:organization) { create(:organization) }

  describe "PUT /admin/organizations/:id" do
    let(:update_params) do
      {
        name: "FooBar",
        premium_integrations: ["okta"]
      }
    end

    it "updates an organization" do
      admin_put(
        "/admin/organizations/#{organization.id}",
        update_params,
        admin_headers
      )

      expect(response).to have_http_status(:success)

      expect(json[:organization][:name]).to eq("FooBar")
      expect(json[:organization][:premium_integrations]).to include("okta")

      organization.reload

      expect(organization.name).to eq("FooBar")
      expect(organization.premium_integrations).to include("okta")
    end
  end

  describe "POST /admin/organizations" do
    let(:create_params) do
      {
        name: "NewCo",
        email: "admin@newco.test",
        premium_integrations: ["okta"]
      }
    end

    before { create(:role, :admin) }

    context "with a valid admin key" do
      it "creates an organization and returns 201" do
        expect do
          admin_post("/admin/organizations", create_params, admin_headers)
        end.to change(Organization, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(json[:organization][:name]).to eq("NewCo")
        expect(json[:invite_url]).to be_present
        expect(json[:organization][:premium_integrations]).to include("okta")
      end
    end

    context "with an invalid email" do
      it "returns an error without creating the organization" do
        expect do
          admin_post("/admin/organizations", create_params.merge(email: "not-an-email"), admin_headers)
        end.not_to change(Organization, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Invite.count).to eq(0)
      end
    end

    context "with an invalid admin key" do
      it "returns unauthorized" do
        admin_post("/admin/organizations", create_params, admin_headers("wrong"))
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "without an admin key" do
      it "returns unauthorized" do
        admin_post("/admin/organizations", create_params)
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
