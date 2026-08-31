# frozen_string_literal: true

require "rails_helper"

RSpec.describe StreamingDestinations::BaseDestination do
  describe "single table inheritance" do
    it "shares one table with its subclasses" do
      expect(described_class.table_name).to eq("streaming_destinations")
      expect(StreamingDestinations::KinesisDestination.table_name).to eq("streaming_destinations")
    end

    it "loads a persisted record as its concrete subclass" do
      destination = create(:kinesis_destination)

      expect(described_class.find(destination.id)).to be_a(StreamingDestinations::KinesisDestination)
    end

    it "exposes the destination through the organization association" do
      destination = create(:kinesis_destination)

      expect(destination.organization.streaming_destinations).to contain_exactly(destination)
    end
  end

  describe "#subscribed?" do
    subject { destination.subscribed?("subscription.updated") }

    context "when event_types is nil" do
      let(:destination) { build(:kinesis_destination, event_types: nil) }

      it { is_expected.to be(true) }
    end

    context "when event_types includes the type" do
      let(:destination) { build(:kinesis_destination, event_types: ["subscription.updated", "wallet.updated"]) }

      it { is_expected.to be(true) }
    end

    context "when event_types excludes the type" do
      let(:destination) { build(:kinesis_destination, event_types: ["wallet.updated"]) }

      it { is_expected.to be(false) }
    end

    context "when event_types is empty" do
      let(:destination) { build(:kinesis_destination, event_types: []) }

      it { is_expected.to be(false) }
    end
  end

  describe "#deliver_service_class" do
    it "raises on the abstract parent" do
      expect { described_class.new.deliver_service_class }.to raise_error(NotImplementedError)
    end
  end

  describe "validations" do
    it "requires a name" do
      destination = build(:kinesis_destination, name: nil)

      expect(destination).not_to be_valid
      expect(destination.errors.where(:name, :blank)).to be_present
    end

    it "rejects a code already used in the same organization" do
      existing = create(:kinesis_destination)
      duplicate = build(:kinesis_destination, organization: existing.organization, code: existing.code)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors.where(:code, :taken)).to be_present
    end

    it "allows the same code in another organization" do
      existing = create(:kinesis_destination)

      expect(build(:kinesis_destination, code: existing.code)).to be_valid
    end

    it "ignores discarded records, so a discarded code can be reused" do
      existing = create(:kinesis_destination)
      existing.discard!

      expect(build(:kinesis_destination, organization: existing.organization, code: existing.code)).to be_valid
    end
  end

  describe "discarding" do
    it { expect(described_class).to be_soft_deletable }

    it "hides discarded destinations from the default scope" do
      destination = create(:kinesis_destination)
      destination.discard!

      expect(described_class.find_by(id: destination.id)).to be_nil
      expect(described_class.with_discarded.find_by(id: destination.id)).to eq(destination)
    end
  end
end
