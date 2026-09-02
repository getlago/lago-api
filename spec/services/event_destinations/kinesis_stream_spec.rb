# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventDestinations::KinesisStream do
  let(:organization) { create(:organization) }

  describe ".for" do
    subject { described_class.for(organization) }

    context "when LAGO_EVENT_DESTINATION_ORG_ID is absent" do
      before { stub_const("ENV", ENV.to_h.except("LAGO_EVENT_DESTINATION_ORG_ID")) }

      it { is_expected.to be_nil }
    end

    context "when LAGO_EVENT_DESTINATION_ORG_ID does not match the organization" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_EVENT_DESTINATION_ORG_ID" => create(:organization).id)) }

      it { is_expected.to be_nil }
    end

    context "when the organization is nil" do
      subject { described_class.for(nil) }

      before { stub_const("ENV", ENV.to_h.merge("LAGO_EVENT_DESTINATION_ORG_ID" => organization.id)) }

      it { is_expected.to be_nil }
    end

    context "when LAGO_EVENT_DESTINATION_ORG_ID matches the organization" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_EVENT_DESTINATION_ORG_ID" => organization.id)) }

      it { is_expected.to be_a(described_class) }
    end
  end

  describe "#stream_arn" do
    before { stub_const("ENV", ENV.to_h.merge("LAGO_EVENT_DESTINATION_KINESIS_STREAM_ARN" => "arn:aws:kinesis:eu-west-1:123456789012:stream/usage")) }

    it "returns the configured ARN" do
      expect(described_class.new.stream_arn).to eq("arn:aws:kinesis:eu-west-1:123456789012:stream/usage")
    end
  end

  describe "#region" do
    before { stub_const("ENV", ENV.to_h.merge("LAGO_EVENT_DESTINATION_KINESIS_REGION" => "eu-west-1")) }

    it "returns the configured region" do
      expect(described_class.new.region).to eq("eu-west-1")
    end
  end

  describe "#log_only?" do
    context "when LAGO_EVENT_DESTINATION_TRANSPORT is absent" do
      before { stub_const("ENV", ENV.to_h.except("LAGO_EVENT_DESTINATION_TRANSPORT")) }

      it { expect(described_class.new).to be_log_only }
    end

    context "when LAGO_EVENT_DESTINATION_TRANSPORT is log" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_EVENT_DESTINATION_TRANSPORT" => "log")) }

      it { expect(described_class.new).to be_log_only }
    end

    context "when LAGO_EVENT_DESTINATION_TRANSPORT is kinesis" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_EVENT_DESTINATION_TRANSPORT" => "kinesis")) }

      it { expect(described_class.new).not_to be_log_only }
    end

    # A declared-but-blank env var is not absent, so it must not fall through to live delivery.
    context "when LAGO_EVENT_DESTINATION_TRANSPORT is blank" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_EVENT_DESTINATION_TRANSPORT" => "")) }

      it { expect(described_class.new).to be_log_only }
    end

    context "when LAGO_EVENT_DESTINATION_TRANSPORT is unrecognized" do
      before do
        stub_const("ENV", ENV.to_h.merge("LAGO_EVENT_DESTINATION_TRANSPORT" => "Kinesis"))
        allow(Rails.logger).to receive(:warn)
      end

      it "falls back to log-only and warns" do
        expect(described_class.new).to be_log_only

        expect(Rails.logger).to have_received(:warn).with(/unrecognized LAGO_EVENT_DESTINATION_TRANSPORT/)
      end
    end
  end
end
