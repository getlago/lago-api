# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Deprecation, type: :model, cache: :redis do
  let(:organization) { create(:organization) }
  let(:feature_name) { 'event_legacy' }

  before do
    Rails.cache.write("deprecation:#{feature_name}:#{organization.id}:last_seen_at", "2024-05-22T14:58:20.280Z")
    Rails.cache.increment("deprecation:#{feature_name}:#{organization.id}:count", 101)
  end

  describe '.report' do
    it 'writes to cache' do
      freeze_time do
        described_class.report(feature_name, organization.id)

        expect(Rails.cache.read("deprecation:#{feature_name}:#{organization.id}:last_seen_at")).to eq(Time.zone.now.utc)
        expect(Rails.cache.read("deprecation:#{feature_name}:#{organization.id}:count", raw: true)).to eq("102")
      end
    end
  end

  describe '.get' do
    it 'returns deprecation data for an organization' do
      expect(described_class.get(feature_name, organization.id)).to eq({
        organization_id: organization.id,
        last_seen_at: "2024-05-22T14:58:20.280Z",
        count: 101
      })
    end
  end

  describe '.get_all' do
    it 'returns deprecation data for all organizations' do
      expect(described_class.get_all(feature_name)).to eq([{
        organization_id: organization.id,
        last_seen_at: "2024-05-22T14:58:20.280Z",
        count: 101
      }])
    end
  end

  describe '.get_all_as_csv' do
    it 'returns deprecation data for all organizations' do
      csv = "organization_id,last_seen_at,count\n"
      csv += "#{organization.id},2024-05-22T14:58:20.280Z,101\n"
      expect(described_class.get_all_as_csv(feature_name)).to eq(csv)
    end
  end
end
