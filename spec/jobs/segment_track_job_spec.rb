require 'rails_helper'

describe SegmentTrackJob, job: true do
  subject { described_class }

  describe '.perform' do
    let(:event) { 'event' }
    let(:properties) do
      { method: 1 }
    end

    it "calls SegmentTrackJob's process method" do
      expect(SEGMENT_CLIENT).to receive(:track)
        .with(
          user_id: CurrentContext.membership,
          event: event,
          properties: {
            method: 1,
            hosting_type: ENV['HOSTING_TYPE'],
            version: Utils::VersionService.new.version.version.number
          }
        )

      subject.perform_now(event: event, properties: properties)
    end
  end
end
