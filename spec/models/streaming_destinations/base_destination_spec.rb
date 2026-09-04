# frozen_string_literal: true

require "rails_helper"

RSpec.describe StreamingDestinations::BaseDestination, type: :model do
  subject(:destination) { create(:kinesis_destination) }

  describe "associations" do
    it do
      expect(destination).to belong_to(:organization)
    end
  end

  describe "validations" do
    it do
      expect(destination).to validate_presence_of(:event_types)
    end

    describe "event_types validation" do
      it "rejects an empty array" do
        destination = build(:kinesis_destination, event_types: [])

        expect(destination).not_to be_valid
        expect(destination.errors.where(:event_types, :blank)).to be_present
      end

      it "rejects an unknown event type" do
        destination = build(:kinesis_destination, event_types: ["customer_usage.refresed"])

        expect(destination).not_to be_valid
        expect(destination.errors.where(:event_types, :inclusion)).to be_present
      end

      it "rejects an event type already claimed by another destination of the organization" do
        organization = create(:organization)
        create(:kinesis_destination, organization:, event_types: ["customer_usage.refreshed"])

        destination = build(:kinesis_destination, organization:, event_types: ["customer_usage.refreshed"])

        expect(destination).not_to be_valid
        expect(destination.errors.where(:event_types, :already_claimed)).to be_present
      end

      it "allows the same event type on another organization" do
        create(:kinesis_destination, event_types: ["customer_usage.refreshed"])

        expect(build(:kinesis_destination, event_types: ["customer_usage.refreshed"])).to be_valid
      end

      it "does not conflict with itself on update" do
        destination = create(:kinesis_destination)

        expect(destination.update(settings: destination.settings.merge("region" => "us-east-1"))).to be true
      end
    end
  end

  describe ".for_event" do
    let(:organization) { create(:organization) }
    let!(:destination) { create(:kinesis_destination, organization:, event_types: ["customer_usage.refreshed"]) }

    it "returns a destination whose event_types contain the event type" do
      expect(described_class.for_event(organization, "customer_usage.refreshed")).to eq([destination])
    end

    it "does not return a destination without the event type" do
      destination.update_column(:event_types, ["wallet.updated"]) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.for_event(organization, "customer_usage.refreshed")).to be_empty
    end

    it "does not return another organization's destination" do
      expect(described_class.for_event(create(:organization), "customer_usage.refreshed")).to be_empty
    end

    it "is the only lookup that works, find_by on the array column raises" do
      expect { described_class.find_by(event_types: "customer_usage.refreshed") }
        .to raise_error(ActiveRecord::StatementInvalid, /malformed array literal/)
    end
  end

  describe "secrets" do
    it "round-trips through SecretsStorable" do
      destination.push_to_secrets(key: "api_key", value: "secret-value")
      destination.save!

      expect(destination.reload.get_from_secrets("api_key")).to eq("secret-value")
    end
  end
end
