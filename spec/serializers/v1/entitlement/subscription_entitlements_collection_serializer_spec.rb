# frozen_string_literal: true

require "rails_helper"

RSpec.describe V1::Entitlement::SubscriptionEntitlementsCollectionSerializer, type: :serializer do
  subject(:serializer) { described_class.new(collection, nil, collection_name: "entitlements") }

  let(:organization) { create(:organization) }
  let(:collection) { Entitlement::SubscriptionEntitlement.for_subscription(subscription).where(removed: false) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:privilege1) { create(:privilege, organization:, feature:, code: "max", value_type: "integer") }
  let(:privilege2) { create(:privilege, organization:, feature:, code: "reset", value_type: "string") }
  let(:privilege3) { create(:privilege, organization:, feature:, code: "root?", value_type: "boolean") }

  let(:entitlement) { create(:entitlement, plan:, feature:) }
  let(:entitlement_value1) { create(:entitlement_value, entitlement:, privilege: privilege1, value: 30) }
  let(:entitlement_value2) { create(:entitlement_value, entitlement:, privilege: privilege2, value: :email) }

  let(:sub_entitlement) { create(:entitlement, subscription:, plan: nil, feature:) }
  let(:entitlement_value3) { create(:entitlement_value, entitlement: sub_entitlement, privilege: privilege3, value: true) }
  let(:entitlement_value25) { create(:entitlement_value, entitlement: sub_entitlement, privilege: privilege2, value: :slack) }

  let(:feature2) { create(:feature, organization:, code: "storage", name: nil, description: nil) }
  let(:privilege4) { create(:privilege, organization:, feature: feature2, code: "limit", name: "L", value_type: "integer") }
  let(:entitlement2) { create(:entitlement, plan:, feature: feature2) }
  let(:entitlement_value4) { create(:entitlement_value, entitlement: entitlement2, privilege: privilege4, value: 100) }

  before do
    entitlement
    entitlement_value1
    entitlement_value2
    entitlement_value25
    entitlement_value3
    entitlement2
    entitlement_value4
  end

  describe "#serialize" do
    subject { serializer.serialize }

    it "returns the correct structure" do
      expect(subject).to have_key(:entitlements)
      expect(subject[:entitlements]).to be_an(Array)
      expect(subject[:entitlements].length).to eq(2)
    end

    it "groups entitlements by feature" do
      seats = subject[:entitlements].find { |e| e[:code] == "seats" }.deep_symbolize_keys

      expect(seats).to include({
        code: "seats",
        name: "Feature Name",
        description: "Feature Description"
      })
      expect(seats[:privileges]).to contain_exactly({
        code: "root?",
        name: nil,
        value_type: "boolean",
        config: {},
        value: true,
        plan_value: nil,
        override_value: true
      }, {
        code: "max",
        name: nil,
        value_type: "integer",
        config: {},
        value: 30,
        plan_value: 30,
        override_value: nil
      }, {
        code: "reset",
        name: nil,
        value_type: "string",
        config: {},
        value: "slack",
        plan_value: "email",
        override_value: "slack"
      })
      expect(seats[:overrides]).to eq({
        reset: "slack",
        root?: true
      })

      storage = subject[:entitlements].find { |e| e[:code] == "storage" }.deep_symbolize_keys

      expect(storage).to include({
        code: "storage",
        name: nil,
        description: nil
      })
      expect(storage[:privileges]).to contain_exactly({
        code: "limit",
        name: "L",
        value_type: "integer",
        config: {},
        value: 100,
        plan_value: 100,
        override_value: nil
      })
      expect(storage[:overrides]).to eq({})
    end

    context "when there are no entitlements" do
      let(:collection) { Entitlement::SubscriptionEntitlement.none }

      it "returns empty array" do
        expect(subject[:entitlements]).to eq([])
      end
    end
  end
end
