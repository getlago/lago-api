# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::PrivilegeDestroyService, type: :service do
  subject { described_class.call(privilege:) }

  let(:organization) { create(:organization) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege) { create(:privilege, feature:, code: "max_admins", value_type: "integer") }
  let(:entitlement_value1) { create(:entitlement_value, privilege:, organization:) }
  let(:entitlement_value2) { create(:entitlement_value, privilege:, organization:) }

  before do
    entitlement_value1
    entitlement_value2
    privilege.reload
  end

  describe "#call" do
    it "discards the privilege" do
      expect { subject }.to change { privilege.reload.discarded? }.from(false).to(true)
    end

    it "returns the privilege in the result" do
      result = subject

      expect(result).to be_success
      expect(result.privilege).to eq(privilege)
    end

    context "when privilege is nil" do
      it "returns a not found failure" do
        result = described_class.call(privilege: nil)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("privilege")
      end
    end

    context "when privilege is already discarded" do
      before { privilege.discard! }

      it "still succeeds" do
        expect { subject }.to raise_error(Discard::RecordNotDiscarded)
      end
    end

    context "when privilege has no entitlement values" do
      before do
        entitlement_value1.discard!
        entitlement_value2.discard!
      end

      it "still discards the privilege successfully" do
        expect { subject }.to change { privilege.reload.discarded? }.from(false).to(true)
      end
    end
  end
end
