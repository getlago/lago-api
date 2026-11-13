# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiKeys::CreateMemberKeyService do
  subject(:result) { described_class.call(membership:) }

  let(:organization) { create(:organization) }
  let(:role) { create(:role, organization:, permissions: %w[invoices:view]) }
  let(:membership) { create(:membership, organization:, role:) }

  it "creates a short-lived key carrying the member's permissions" do
    freeze_time do
      api_key = result.api_key

      expect(api_key).to be_persisted
      expect(api_key).to have_attributes(
        organization:,
        membership:,
        expires_at: described_class::EXPIRATION.from_now,
        permissions: ApiKeys::MemberPermissions.for(membership)
      )
      expect(api_key.permissions["invoice"]).to eq(["read"])
    end
  end

  it "keeps the key out of the organization's keys" do
    api_key = result.api_key

    expect(organization.api_keys).not_to include(api_key)
    expect(organization.member_api_keys).to include(api_key)
  end

  it "neither emails the admins nor logs a security event" do
    allow(Utils::SecurityLog).to receive(:produce)

    expect { result }.not_to have_enqueued_mail(ApiKeyMailer, :created)
    expect(Utils::SecurityLog).not_to have_received(:produce)
  end
end
