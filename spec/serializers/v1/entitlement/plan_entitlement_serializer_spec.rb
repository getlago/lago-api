# frozen_string_literal: true

require "rails_helper"

RSpec.describe V1::Entitlement::PlanEntitlementSerializer do
  subject { described_class.new(entitlement) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:entitlement) { create(:entitlement, organization:, feature:, plan:) }
  let(:privilege) { create(:privilege, code: "max", value_type: "integer", feature:, organization:) }
  let(:entitlement_value) { create(:entitlement_value, value: 30, entitlement:, privilege:, organization:) }

  describe "#serialize" do
    before do
      entitlement_value
    end

    it "serializes the entitlement correctly" do
      result = subject.serialize

      expect(result).to include(
        code: "seats",
        name: feature.name,
        description: feature.description
      )
      expect(result[:privileges]["max"]).to include(
        code: "max",
        name: nil,
        value_type: "integer",
        value: 30,
        config: {}
      )
    end
  end
end
