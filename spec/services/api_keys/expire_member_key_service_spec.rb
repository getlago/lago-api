# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiKeys::ExpireMemberKeyService do
  subject(:result) { described_class.call(api_key:) }

  let(:membership) { create(:membership) }
  let(:api_key) { ApiKeys::CreateMemberKeyService.call!(membership:).api_key }
  let(:usage_cache_key) { "api_key_last_used_#{api_key.id}" }

  before { allow(Rails.cache).to receive(:delete).and_call_original }

  it "expires the key and keeps it, so the logs still point to the member" do
    freeze_time do
      result

      expect(ApiKey.unscoped.find(api_key.id)).to have_attributes(expires_at: Time.current, membership:)
    end
  end

  it "records the cached usage and removes the entry" do
    used_at = 1.minute.ago.iso8601
    allow(Rails.cache).to receive(:read).and_call_original
    allow(Rails.cache).to receive(:read).with(usage_cache_key).and_return(used_at)

    result

    expect(ApiKey.unscoped.find(api_key.id).last_used_at).to eq(Time.zone.parse(used_at))
    expect(Rails.cache).to have_received(:delete).with(usage_cache_key)
  end
end
