# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::FeatureDestroyService, type: :service do
  subject { described_class.call(feature:) }

  let(:organization) { create(:organization) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege1) { create(:privilege, feature:, code: "max_admins", value_type: "integer") }
  let(:privilege2) { create(:privilege, feature:, code: "max_users", value_type: "integer") }

  before do
    privilege1
    privilege2
    feature.reload
  end

  describe "#call" do
    it "discards the feature" do
      expect { subject }.to change { feature.reload.discarded? }.from(false).to(true)
    end

    it "discards all privileges associated with the feature" do
      expect { subject }.to change { feature.privileges.kept.count }.by(-2)
    end

    it "returns the feature in the result" do
      result = subject

      expect(result).to be_success
      expect(result.feature).to eq(feature)
    end

    context "when feature is nil" do
      it "returns a not found failure" do
        result = described_class.call(feature: nil)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
      end
    end

    context "when feature is already discarded" do
      before { feature.discard! }

      it "still succeeds" do
        expect { subject }.to raise_error(Discard::RecordNotDiscarded)
      end
    end

    context "when feature has no privileges" do
      before do
        privilege1.discard!
        privilege2.discard!
      end

      it "still discards the feature successfully" do
        expect { subject }.to change { feature.reload.discarded? }.from(false).to(true)
      end
    end
  end
end
