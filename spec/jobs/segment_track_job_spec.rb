# frozen_string_literal: true

require "rails_helper"

describe SegmentTrackJob, job: true do
  subject { described_class }

  describe ".perform" do
    let(:membership_id) { "membership/#{SecureRandom.uuid}" }
    let(:event) { "event" }
    let(:properties) do
      {method: 1}
    end

    before do
      stub_const("ENV", "LAGO_DISABLE_SEGMENT" => "")
      allow(CurrentContext).to receive(:membership).and_return(membership_id)
    end

    it "calls SegmentTrackJob's process method" do
      expect(SEGMENT_CLIENT).to receive(:track)
        .with(
          user_id: membership_id,
          event:,
          properties: {
            method: 1,
            hosting_type: "self",
            version: Utils::VersionService.new.version.version.number
          }
        )

      subject.perform_now(membership_id:, event:, properties:)
    end

    context "when LAGO_CLOUD is true" do
      it "includes hosting type equal to cloud" do
        stub_const("ENV", "LAGO_CLOUD" => "true")

        expect(SEGMENT_CLIENT).to receive(:track).with(
          hash_including(properties: hash_including(hosting_type: "cloud"))
        )

        subject.perform_now(membership_id:, event:, properties:)
      end
    end

    context "when membership is nil" do
      it "sends event to an unidentifiable membership" do
        expect(SEGMENT_CLIENT).to receive(:track).with(
          hash_including(user_id: "membership/unidentifiable")
        )

        subject.perform_now(membership_id: nil, event:, properties:)
      end
    end

    context "when LAGO_DISABLE_SEGMENT is true" do
      it "does not call SegmentTrackJob" do
        stub_const("ENV", "LAGO_DISABLE_SEGMENT" => "true")

        expect(SEGMENT_CLIENT).not_to receive(:track)
        subject.perform_now(membership_id:, event:, properties:)
      end
    end
  end
end
