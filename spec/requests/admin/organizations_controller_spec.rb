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
    let(:actor) { create(:user, email: "cs@getlago.com", cs_admin: true) }

    let(:create_params) do
      {
        name: "NewCo",
        email: "admin@newco.test",
        actor_email: actor.email,
        reason: "New enterprise customer onboarding",
        premium_integrations: ["okta"],
        feature_flags: ["multi_currency"]
      }
    end

    before do
      create(:role, :admin)
      actor
    end

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

      it "records the audit trail of the creation" do
        admin_post("/admin/organizations", create_params, admin_headers)

        organization = Organization.find(json[:organization][:id])
        logs = CsAdminAuditLog.where(organization:)

        expect(logs.pluck(:action).uniq).to eq(["org_created"])
        expect(logs.pluck(:actor_email).uniq).to eq(["cs@getlago.com"])
        expect(logs.pluck(:feature_key)).to match_array(%w[organization okta multi_currency])
        expect(logs.pluck(:reason).uniq).to eq(["New enterprise customer onboarding"])
        expect(logs.map(&:actor_user).uniq).to eq([actor])
      end
    end

    context "without a reason" do
      it "returns a validation error" do
        expect do
          admin_post("/admin/organizations", create_params.except(:reason), admin_headers)
        end.not_to change(Organization, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details][:reason]).to eq(["value_is_mandatory"])
      end
    end

    context "without an actor email" do
      it "returns a validation error" do
        expect do
          admin_post("/admin/organizations", create_params.except(:actor_email), admin_headers)
        end.not_to change(Organization, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details][:actor_email]).to eq(["value_is_mandatory"])
      end
    end

    context "with an actor email matching no user" do
      it "returns a validation error" do
        expect do
          admin_post(
            "/admin/organizations",
            create_params.merge(actor_email: "ghost@getlago.com"),
            admin_headers
          )
        end.not_to change(Organization, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details][:actor_email]).to eq(["value_is_invalid"])
      end
    end

    context "with an invalid email" do
      it "returns an error without creating the organization" do
        expect do
          admin_post("/admin/organizations", create_params.merge(email: "not-an-email"), admin_headers)
        end.not_to change(Organization, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Invite.count).to eq(0)
        expect(CsAdminAuditLog.count).to eq(0)
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
