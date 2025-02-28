# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::CommonFactory do
  describe ".new_instance" do
    context "when source is an instance of Events::Common" do
      let(:source) { build(:common_event) }

      it "returns the source" do
        expect(described_class.new_instance(source:)).to eq(source)
      end
    end

    context "when source is a hash" do
      let(:source) { build(:common_event).as_json }

      it "returns a new instance of Events::Common", :aggregate_failures do
        new_instance = described_class.new_instance(source:)

        expect(new_instance.id).to be_nil
        expect(new_instance.organization_id).to eq(source["organization_id"])
        expect(new_instance.transaction_id).to eq(source["transaction_id"])
        expect(new_instance.external_subscription_id).to eq(source["external_subscription_id"])
        # Keep in mind that we need the milliseconds precision!
        expect(new_instance.timestamp).to eq(Time.zone.at(source["timestamp"].to_f))
        expect(new_instance.code).to eq(source["code"])
        expect(new_instance.properties).to eq(source["properties"])
      end
    end

    context "when source is an instance of Event" do
      let(:source) { create(:event) }

      it "returns a new instance of Events::Common", :aggregate_failures do
        new_instance = described_class.new_instance(source:)

        expect(new_instance.id).to eq(source.id)
        expect(new_instance.organization_id).to eq(source.organization_id)
        expect(new_instance.transaction_id).to eq(source.transaction_id)
        expect(new_instance.external_subscription_id).to eq(source.external_subscription_id)
        expect(new_instance.timestamp).to eq(source.timestamp)
        expect(new_instance.code).to eq(source.code)
        expect(new_instance.properties).to eq(source.properties)
      end
    end

    context "when source is an instance of Clickhouse::EventsRaw", clickhouse: true do
      let(:source) { create(:clickhouse_events_raw) }

      it "returns a new instance of Events::Common", :aggregate_failures do
        new_instance = described_class.new_instance(source:)

        expect(new_instance.id).to be_nil
        expect(new_instance.organization_id).to eq(source.organization_id)
        expect(new_instance.transaction_id).to eq(source.transaction_id)
        expect(new_instance.external_subscription_id).to eq(source.external_subscription_id)
        expect(new_instance.timestamp).to eq(source.timestamp)
        expect(new_instance.code).to eq(source.code)
        expect(new_instance.properties).to eq(source.properties)
      end
    end
  end
end
