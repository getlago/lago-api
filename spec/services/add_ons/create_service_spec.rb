# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AddOns::CreateService, type: :service do
  subject(:create_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'create' do
    let(:create_args) do
      {
        name: 'Super Add-on',
        code: 'free-beer-for-us',
        description: 'This is description',
        organization_id: organization.id,
        amount_cents: 100,
        amount_currency: 'EUR',
      }
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates an add-on' do
      expect { create_service.create(**create_args) }
        .to change(AddOn, :count).by(1)
    end

    it 'calls SegmentTrackJob' do
      add_on = create_service.create(**create_args).add_on

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'add_on_created',
        properties: {
          addon_code: add_on.code,
          addon_name: add_on.name,
          organization_id: add_on.organization_id,
        },
      )
    end

    context 'with validation error' do
      before do
        create(
          :add_on,
          organization: organization,
          code: 'free-beer-for-us',
        )
      end

      it 'returns an error' do
        result = create_service.create(**create_args)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:code]).to eq(['value_already_exist'])
        end
      end
    end
  end
end
