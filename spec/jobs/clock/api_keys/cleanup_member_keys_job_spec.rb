# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::ApiKeys::CleanupMemberKeysJob, job: true do
  subject(:perform) { described_class.perform_now }

  let(:organization) { create(:organization) }
  let(:membership) { create(:membership, organization:) }

  it "deletes the member keys expired for more than a day" do
    old_key = create(:api_key, organization:, membership:, expires_at: 2.days.ago)
    recent_key = create(:api_key, organization:, membership:, expires_at: 1.hour.ago)
    active_key = create(:api_key, organization:, membership:, expires_at: 1.hour.from_now)
    organization_key = create(:api_key, organization:, expires_at: 2.days.ago)

    perform

    remaining = ApiKey.unscoped.where(id: [old_key, recent_key, active_key, organization_key].map(&:id)).pluck(:id)
    expect(remaining).to contain_exactly(recent_key.id, active_key.id, organization_key.id)
  end
end
