# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventsQuery, type: :query do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:event) { create(:event, timestamp: 1.day.ago.to_date, organization:) }

  before { event }

  it "returns a list of events" do
    expect(result).to be_success
    expect(result.events.count).to eq(1)
    expect(result.events).to eq([event])
  end

  context "when events have the ordering criteria" do
    let(:event_2) do
      create(
        :event,
        organization:,
        timestamp: event.timestamp,
        created_at: event.created_at
      ).tap do |event|
        event.update! id: "00000000-0000-0000-0000-000000000000"
      end
    end

    it "returns a consistent list" do
      expect(result).to be_success
      expect(result.events).to eq([event_2, event])
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 10} }

    it "applies the pagination" do
      expect(result).to be_success
      expect(result.events.count).to eq(0)
      expect(result.events.current_page).to eq(2)
    end
  end

  context "with code filter" do
    let(:event2) { create(:event, organization:) }
    let(:filters) { {code: event.code} }

    before { event2 }

    it "applies the filter" do
      expect(result).to be_success
      expect(result.events.count).to eq(1)
    end
  end

  context "with external subscription id filter" do
    let(:event2) { create(:event, organization:) }
    let(:filters) { {external_subscription_id: event.external_subscription_id} }

    before { event2 }

    it "applies the filter" do
      expect(result).to be_success
      expect(result.events.count).to eq(1)
    end
  end

  context "with timestamp from filter" do
    let(:filters) {
      {
        timestamp_from: 2.days.ago.iso8601.to_date.to_s,
        timestamp_to: Date.tomorrow.iso8601.to_date.to_s
      }
    }

    it "applies the filter" do
      expect(result).to be_success
      expect(result.events.count).to eq(1)
    end
  end
end
