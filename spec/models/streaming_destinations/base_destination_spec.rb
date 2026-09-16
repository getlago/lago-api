# frozen_string_literal: true

require "rails_helper"

RSpec.describe StreamingDestinations::BaseDestination, type: :model do
  subject(:destination) { create(:kinesis_destination) }

  it_behaves_like "paper_trail traceable"

  describe "EVENT_TYPES" do
    it "versions every event type, so a breaking payload change can ship as a new type" do
      expect(described_class::EVENT_TYPES).to all(match(/\.v\d+\z/))
    end
  end

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
        destination = build(:kinesis_destination, event_types: ["customer_usage.refresed.v1"])

        expect(destination).not_to be_valid
        expect(destination.errors.where(:event_types, :inclusion)).to be_present
      end

      it "rejects an event type already claimed by another destination of the organization" do
        organization = create(:organization)
        create(:kinesis_destination, organization:, event_types: ["customer_usage.refreshed.v1"])

        destination = build(:kinesis_destination, organization:, event_types: ["customer_usage.refreshed.v1"])

        expect(destination).not_to be_valid
        expect(destination.errors.where(:event_types, :taken)).to be_present
      end

      it "keeps the claim while inactive, so one destination per event type holds whatever its state" do
        organization = create(:organization)
        create(:kinesis_destination, organization:, event_types: ["customer_usage.refreshed.v1"], active: false)

        destination = build(:kinesis_destination, organization:, event_types: ["customer_usage.refreshed.v1"])

        expect(destination).not_to be_valid
        expect(destination.errors.where(:event_types, :taken)).to be_present
      end

      it "allows the same event type on another organization" do
        create(:kinesis_destination, event_types: ["customer_usage.refreshed.v1"])

        expect(build(:kinesis_destination, event_types: ["customer_usage.refreshed.v1"])).to be_valid
      end

      it "does not conflict with itself on update" do
        destination = create(:kinesis_destination)

        expect(destination.update(settings: destination.settings.merge("region" => "us-east-1"))).to be true
      end
    end
  end

  describe "#producer" do
    it "is the subtype's responsibility" do
      expect { described_class.new.producer }.to raise_error(NotImplementedError)
    end
  end

  describe "#event_types_for" do
    subject(:destination) { create(:kinesis_destination) }

    let(:customer) { create(:customer, organization: destination.organization) }
    let(:plan) { create(:plan, organization: destination.organization, code: "self_serve_monthly") }
    let(:subscription) { create(:subscription, customer:, plan:) }

    it "returns every subscribed type when no plan is excluded" do
      expect(destination.event_types_for(subscription)).to match_array(described_class::EVENT_TYPES)
    end

    it "drops the full usage type for an excluded plan" do
      destination.customer_full_usage_excluded_plan_codes = ["self_serve_monthly"]

      expect(destination.event_types_for(subscription)).to eq([described_class::CURRENT_USAGE_EVENT_TYPE])
    end

    it "keeps the full usage type for a plan that is not excluded" do
      destination.customer_full_usage_excluded_plan_codes = ["another_plan"]

      expect(destination.event_types_for(subscription)).to include(described_class::FULL_USAGE_EVENT_TYPE)
    end
  end

  describe ".streams_event?" do
    let(:organization) { create(:organization) }

    it "is true when the organization has a destination for the event" do
      create(:kinesis_destination, organization:, event_types: ["customer_usage.refreshed.v1"])

      expect(described_class.streams_event?(organization, "customer_usage.refreshed.v1")).to be true
    end

    it "is false when it does not" do
      expect(described_class.streams_event?(organization, "customer_usage.refreshed.v1")).to be false
    end
  end

  describe ".for_event" do
    let(:organization) { create(:organization) }
    let!(:destination) { create(:kinesis_destination, organization:, event_types: ["customer_usage.refreshed.v1"]) }

    it "returns a destination whose event_types contain the event type" do
      expect(described_class.for_event(organization, "customer_usage.refreshed.v1")).to eq([destination])
    end

    it "excludes an inactive destination, so deactivating stops delivery without losing its settings" do
      destination.update!(active: false)

      expect(described_class.for_event(organization, "customer_usage.refreshed.v1")).to be_empty
    end

    it "does not return a destination without the event type" do
      destination.update_column(:event_types, ["wallet.updated"]) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.for_event(organization, "customer_usage.refreshed.v1")).to be_empty
    end

    it "does not return another organization's destination" do
      expect(described_class.for_event(create(:organization), "customer_usage.refreshed.v1")).to be_empty
    end

    it "is the only lookup that works, find_by on the array column raises" do
      expect { described_class.find_by(event_types: "customer_usage.refreshed.v1") }
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
