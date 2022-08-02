# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscription, type: :model do
  describe '.upgraded?' do
    let(:previous_subscription) { nil }
    let(:plan) { create(:plan) }

    let(:subscription) do
      create(
        :subscription,
        previous_subscription: previous_subscription,
        plan: plan,
      )
    end

    context 'without next subscription' do
      it { expect(subscription).not_to be_upgraded }
    end

    context 'with next subscription' do
      let(:previous_plan) { create(:plan) }
      let(:previous_subscription) do
        create(:subscription, plan: previous_plan)
      end

      before { subscription }

      it { expect(previous_subscription).to be_upgraded }

      it { expect(previous_subscription.next_pending_start_date).to be nil }

      context 'when previous plan was more expensive' do
        let(:previous_plan) do
          create(:plan, amount_cents: plan.amount_cents + 10)
        end

        it { expect(previous_subscription).not_to be_upgraded }
      end

      context 'when plans have different intervals' do
        before do
          previous_plan.update!(interval: 'monthly')
          plan.update!(interval: 'yearly')
        end

        it { expect(previous_subscription).not_to be_upgraded }
      end

      context 'when next subscription is pending' do
        before do
          subscription.update!(status: :pending)
        end

        it { expect(previous_subscription.next_pending_start_date).not_to be nil }
      end
    end
  end

  describe '.downgraded?' do
    let(:previous_subscription) { nil }
    let(:plan) { create(:plan, amount_cents: 100) }

    let(:subscription) do
      create(
        :subscription,
        previous_subscription: previous_subscription,
        plan: plan,
      )
    end

    context 'without next subscription' do
      it { expect(subscription).not_to be_downgraded }
    end

    context 'with next subscription' do
      let(:previous_plan) { create(:plan, amount_cents: 200) }
      let(:previous_subscription) do
        create(:subscription, plan: previous_plan)
      end

      before { subscription }

      it { expect(previous_subscription).to be_downgraded }

      context 'when previous plan was less expensive' do
        let(:previous_plan) do
          create(:plan, amount_cents: plan.amount_cents - 10)
        end

        it { expect(previous_subscription).not_to be_downgraded }
      end

      context 'when plans have different intervals' do
        before do
          previous_plan.update!(interval: 'yearly')
          plan.update!(interval: 'monthly')
        end

        it { expect(previous_subscription).not_to be_downgraded }
      end
    end
  end

  describe '.trial_end_date' do
    let(:plan) { create(:plan, trial_period: 3) }
    let(:subscription) { create(:active_subscription, plan: plan) }

    it 'returns the trial end date' do
      trial_end_date = subscription.trial_end_date

      aggregate_failures do
        expect(trial_end_date).to be_present
        expect(trial_end_date).to eq(subscription.started_at.to_date + 3.days)
      end
    end

    context 'when plan has no trial' do
      let(:plan) { create(:plan) }

      it 'returns nil' do
        expect(subscription.trial_end_date).to be_nil
      end
    end
  end

  describe '.valid_unique_id' do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization: organization) }
    let(:plan) { create(:plan) }
    let(:unique_id) { SecureRandom.uuid }
    let(:subscription) { create(:active_subscription, plan: plan, customer: customer) }
    let(:new_subscription) { build(:active_subscription, plan: plan, unique_id: unique_id, customer: customer) }

    before { subscription }

    context 'when unique_id is unique' do
      it 'does not raise validation error if unique_id is unique' do
        expect(new_subscription).to be_valid
      end
    end

    context 'when unique_id is NOT unique' do
      let(:unique_id) { subscription.unique_id }

      it 'raises validation error' do
        expect(new_subscription).not_to be_valid
      end
    end
  end
end
