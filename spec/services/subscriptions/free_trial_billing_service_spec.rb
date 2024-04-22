# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::FreeTrialBillingService, type: :service do
  subject(:service) { described_class.new(timestamp:) }

  describe '#call' do
    let(:timestamp) { Time.zone.parse('2024-04-15T13:00:00') }
    let(:plan) { create(:plan, trial_period: 10, pay_in_advance: true) }

    context 'without any ending trial subscriptions' do
      it 'does not set trial_ended_at', :aggregate_failures do
        sub1 = create(:subscription, plan:, started_at: 2.days.ago)

        expect { service.call }.not_to change { sub1.reload.trial_ended_at }.from(nil)
      end
    end

    xcontext 'with ending trial subscriptions' do
      it 'sets trial_ended_at to trial end date' do
        sub = create(:subscription, plan:, started_at: Time.zone.parse('2024-04-05T12:12:00'))
        sub2 = create(:subscription, plan:, started_at: 15.days.ago)
        service.call
        expect(sub.reload.trial_ended_at).to match_datetime(sub.trial_end_datetime)
        expect(sub2.reload.trial_ended_at).to match_datetime(sub2.trial_end_datetime)
      end
    end

    context 'with trial ended due to previous subscription with the same external_id' do
      it 'sets trial_ended_at' do
        customer = create(:customer)
        attr = { customer:, plan:, external_id: 'abc123' }
        started_at = timestamp - 10.days - 1.hour
        create(:subscription, started_at:, terminated_at: 6.days.ago, status: :terminated, **attr)
        sub = create(:subscription, started_at: 6.days.ago, **attr)

        expect { service.call }.to change { sub.reload.trial_ended_at }.from(nil).to(sub.trial_end_datetime)
      end
    end

    context 'with customer timezone' do
      let(:timestamp) { DateTime.parse('2024-03-11 13:03:00 UTC') }

      it 'sets trial_ended_at to the expected subscription (timezone is irrelevant)', :aggregate_failures do
        started_at = DateTime.parse('2024-03-01 12:00:00 UTC')
        customer = create(:customer, timezone: 'America/Los_Angeles')
        sub = create(:subscription, plan:, customer:, started_at:)
        service.call
        expect(sub.reload.trial_ended_at).to match_datetime(sub.trial_end_datetime)
      end
    end
  end
end
