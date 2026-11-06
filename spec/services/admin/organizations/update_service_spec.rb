# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Organizations::UpdateService do
  subject(:update_service) { described_class.new(organization:, params:) }

  let(:organization) { create(:organization) }

  let(:params) do
    {
      name: "FooBar",
      premium_integrations: ["okta"]
    }
  end

  describe "#call" do
    it "updates the organization" do
      result = update_service.call

      expect(result.organization.name).to eq("FooBar")
      expect(result.organization.premium_integrations).to include("okta")

      organization.reload

      expect(organization.reload.name).to eq("FooBar")
      expect(organization.premium_integrations).to include("okta")
    end

    context "when the organization has a sandbox" do
      let(:sandbox) { create(:organization, :sandbox, production_organization: organization) }

      before { sandbox }

      it "gives the sandbox the same premium integrations" do
        update_service.call

        expect(sandbox.reload.premium_integrations).to eq(["okta"])
      end
    end

    context "when the organization is a sandbox" do
      let(:organization) { create(:organization, :sandbox) }

      it "refuses premium integrations but accepts a rename" do
        expect(update_service.call.error.code).to eq("sandbox_managed_by_production")
        expect(described_class.call(organization: organization.reload, params: {name: "Renamed"})).to be_success
        expect(organization.reload).to have_attributes(name: "Renamed", premium_integrations: [])
      end
    end

    context "when organization is nil" do
      let(:organization) { nil }

      it "returns a not found error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
      end
    end
  end
end
