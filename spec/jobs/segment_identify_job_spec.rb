# frozen_string_literal: true

require 'rails_helper'

describe SegmentIdentifyJob, job: true do
  subject { described_class }

  describe '.perform' do
    let(:membership_id) { "membership/#{membership.id}" }
    let(:membership) { create(:membership) }

    before do
      ENV['LAGO_DISABLE_SEGMENT'] = ''
      allow(CurrentContext).to receive(:membership).and_return(membership_id)
    end

    it "calls SegmentIdentifyJob's process method" do
      expect(SEGMENT_CLIENT).to receive(:identify)
        .with(
          user_id: membership_id,
          traits: {
            created_at: membership.created_at,
            hosting_type: 'self',
            version: Utils::VersionService.new.version.version.number,
            organization_name: membership.organization.name,
            email: membership.user.email,
          },
        )

      subject.perform_now(membership_id:)
    end

    context 'when LAGO_CLOUD is true' do
      before do
        ENV['LAGO_CLOUD'] = 'true'
      end

      it 'includes hosting type equal to cloud' do
        expect(SEGMENT_CLIENT).to receive(:identify).with(
          hash_including(traits: hash_including(hosting_type: 'cloud')),
        )

        subject.perform_now(membership_id:)
      end
    end

    context 'when membership is nil' do
      it 'does not send any events' do
        expect(SEGMENT_CLIENT).not_to receive(:identify)

        subject.perform_now(membership_id: nil)
      end
    end

    context 'when membership is unidentifiable' do
      it 'does not send any events' do
        expect(SEGMENT_CLIENT).not_to receive(:identify)

        subject.perform_now(membership_id: 'membership/unidentifiable')
      end
    end

    context 'when LAGO_DISABLE_SEGMENT is true' do
      it 'does not call SegmentIdentifyJob' do
        ENV['LAGO_DISABLE_SEGMENT'] = 'true'

        expect(SEGMENT_CLIENT).not_to receive(:identify)
        subject.perform_now(membership_id:)
      end
    end
  end
end
