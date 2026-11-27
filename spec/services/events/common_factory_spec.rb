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
      subject(:new_instance) { described_class.new_instance(source:) }

      let(:source) { build(:common_event).as_json }

      it "returns a new instance of Events::Common" do
        new_instance = described_class.new_instance(source:)

        expect(new_instance.id).to be_nil
        expect(new_instance.organization_id).to eq(source["organization_id"])
        expect(new_instance.transaction_id).to eq(source["transaction_id"])
        expect(new_instance.external_subscription_id).to eq(source["external_subscription_id"])
        expect(new_instance.timestamp).to eq(Events::Common.timestamp_from_source(source))
        expect(new_instance.created_at).to be_nil
        expect(new_instance.code).to eq(source["code"])
        expect(new_instance.properties).to eq(source["properties"])
      end

      context "when the serialized timestamp loses precision as a float" do
        let(:timestamp) { Time.zone.parse("2026-05-22 10:04:50.227587000 +0000") }
        let(:source) { build(:common_event, timestamp:).as_json }

        it "preserves the precise timestamp" do
          new_instance = described_class.new_instance(source:)

          expect(Time.zone.at(source["timestamp"].to_f).usec).to eq(227586)
          expect(new_instance.timestamp).to eq(timestamp)
          expect(new_instance.timestamp.usec).to eq(227587)
        end
      end

      context "when created_at is serialized" do
        let(:created_at) { Time.zone.parse("2026-05-22 10:04:50.227587123 +0000") }
        let(:timestamp) { Time.zone.parse("2026-05-22 10:04:50.227587000 +0000") }
        let(:source) do
          JSON.parse(JSON.generate(build(:common_event, timestamp:, created_at:).as_json))
        end

        it "preserves created_at microsecond precision through JSON" do
          expect(new_instance.created_at).to eq(created_at)
          expect(new_instance.created_at.nsec).to eq(created_at.nsec)
        end
      end

      context "when created_at is missing" do
        let(:source) { build(:common_event).as_json.except("created_at") }

        it { expect(new_instance.created_at).to be_nil }
      end

      context "when created_at is null" do
        let(:source) { build(:common_event).as_json.merge("created_at" => nil) }

        it { expect(new_instance.created_at).to be_nil }
      end

      context "when created_at is malformed" do
        let(:source) { build(:common_event).as_json.merge("created_at" => "invalid") }

        it { expect(new_instance.created_at).to be_nil }
      end
    end

    context "when source is an instance of Event" do
      let(:source) { create(:event) }

      it "returns a new instance of Events::Common" do
        new_instance = described_class.new_instance(source:)

        expect(new_instance.id).to eq(source.id)
        expect(new_instance.organization_id).to eq(source.organization_id)
        expect(new_instance.transaction_id).to eq(source.transaction_id)
        expect(new_instance.external_subscription_id).to eq(source.external_subscription_id)
        expect(new_instance.timestamp).to eq(source.timestamp)
        expect(new_instance.code).to eq(source.code)
        expect(new_instance.properties).to eq(source.properties)
        expect(new_instance.created_at).to eq(source.created_at)
      end
    end

    context "when source is an instance of Clickhouse::EventsRaw", clickhouse: true do
      let(:source) { create(:clickhouse_events_raw) }

      it "returns a new instance of Events::Common" do
        new_instance = described_class.new_instance(source:)

        expect(new_instance.id).to be_nil
        expect(new_instance.organization_id).to eq(source.organization_id)
        expect(new_instance.transaction_id).to eq(source.transaction_id)
        expect(new_instance.external_subscription_id).to eq(source.external_subscription_id)
        expect(new_instance.timestamp).to eq(source.timestamp)
        expect(new_instance.code).to eq(source.code)
        expect(new_instance.properties).to eq(source.properties)
        expect(new_instance.created_at).to eq(source.created_at)
      end
    end
  end
end
