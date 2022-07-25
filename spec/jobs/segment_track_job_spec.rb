require 'rails_helper'

describe SegmentTrackJob, job: true do
  subject { described_class }

  describe '.perform' do
    let(:membership_id) { SecureRandom.uuid }
    let(:event) { 'event' }
    let(:properties) do
      {
        method: 1
      }
    end

    it "calls SegmentTrackJob's process method" do
      expect(SEGMENT_CLIENT).to receive(:track)
        .with(
          membership_id: membership_id,
          event: event,
          properties: properties
        )

      subject.perform_now(membership_id: membership_id, event: event, properties: properties)
    end
  end
end
