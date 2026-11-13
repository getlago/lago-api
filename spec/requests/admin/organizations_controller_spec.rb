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
        expect(Organization.find_by!(name: "NewCo").default_billing_entity.document_numbering).to eq("per_customer")
      end
    end

    context "with self_serve" do
      include_context "with self-serve enabled"

      # The context replaces ENV, which drops the admin key the helper stubs on it.
      let(:self_serve_env) { {"LAGO_SELF_SERVE_ENABLED" => "true", "ADMIN_API_KEY" => AdminHelper::ADMIN_API_KEY} }

      it "creates the organization and its sandbox" do
        expect do
          admin_post("/admin/organizations", create_params.merge(self_serve: true), admin_headers)
        end.to change(Organization, :count).by(2)

        expect(response).to have_http_status(:created)
        production = Organization.find(json[:organization][:id])
        expect(json[:organization]).to include(self_serve: true, environment: "production",
          production_organization_id: nil, sandbox_organization_id: production.sandbox_organization.id)
        expect(json[:sandbox_organization]).to include(id: production.sandbox_organization.id, environment: "sandbox",
          production_organization_id: production.id, sandbox_organization_id: nil)
      end

      it "numbers both organizations per customer" do
        admin_post("/admin/organizations", create_params.merge(self_serve: true), admin_headers)

        production = Organization.find(json[:organization][:id])
        expect([production, production.sandbox_organization].map { it.default_billing_entity.document_numbering })
          .to eq(%w[per_customer per_customer])
      end

      it "refuses a value that is not a boolean" do
        expect do
          admin_post("/admin/organizations", create_params.merge(self_serve: "no"), admin_headers)
        end.not_to change(Organization, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "without self_serve" do
      it "creates no sandbox" do
        admin_post("/admin/organizations", create_params, admin_headers)

        expect(json[:sandbox_organization]).to be_nil
        expect(json[:organization]).to include(self_serve: false, environment: "production")
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
