require 'rails_helper'

describe SegmentTrackJob, job: true do
  subject { described_class }

  describe '.perform' do
    let(:membership_id) { CurrentContext.membership }
    let(:event) { 'event' }
    let(:properties) do
      { method: 1 }
    end

    it "calls SegmentTrackJob's process method" do
      expect(SEGMENT_CLIENT).to receive(:track)
        .with(
          user_id: membership_id,
          event: event,
          properties: {
            method: 1,
            hosting_type: 'self',
            version: Utils::VersionService.new.version.version.number
          }
        )

      subject.perform_now(membership_id: membership_id, event: event, properties: properties)
    end

    context 'when LAGO_CLOUD is true' do
      it 'includes hosting type equal to cloud' do
        stub_const('ENV', 'LAGO_CLOUD' => 'true')

        expect(SEGMENT_CLIENT).to receive(:track).with(
          hash_including(properties: hash_including(hosting_type: 'cloud'))
        )

        subject.perform_now(membership_id: membership_id, event: event, properties: properties)
      end
    end
  end
end
