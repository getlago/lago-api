# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscription, type: :model do
  describe '#upgraded?' do
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
    end
  end

  describe '#downgraded?' do
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

  describe '#trial_end_date' do
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

    context 'with a previous subscription' do
      let(:subscription) do
        create(
          :active_subscription,
          previous_subscription: previous_subscription,
          started_at: Time.zone.yesterday,
          plan: plan,
          external_id: 'sub_id',
          customer: previous_subscription.customer,
        )
      end
      let(:previous_subscription) do
        create(:subscription, started_at: Time.current.last_month, external_id: 'sub_id', status: :terminated)
      end

      it 'takes previous subscription started_at into account' do
        trial_end_date = subscription.trial_end_date

        aggregate_failures do
          expect(trial_end_date).to be_present
          expect(trial_end_date).to eq(previous_subscription.started_at.to_date + 3.days)
        end
      end
    end
  end

  describe '#initial_started_at' do
    let(:customer) { create(:customer) }
    let(:subscription) do
      create(
        :subscription,
        previous_subscription: previous_subscription,
        started_at: Time.zone.yesterday,
        external_id: 'sub_id',
        customer: customer,
      )
    end

    let(:previous_subscription) { nil }

    it 'returns the subscription started_at' do
      expect(subscription.initial_started_at).to eq(subscription.started_at)
    end

    context 'with a previous subscription' do
      let(:previous_subscription) do
        create(
          :subscription,
          started_at: Time.current.last_month,
          status: :terminated,
          external_id: 'sub_id',
          customer: customer,
        )
      end

      it 'returns the previous subscription started_at' do
        expect(subscription.initial_started_at.to_date).to eq(previous_subscription.started_at.to_date)
      end
    end

    context 'with two previous subscriptions' do
      let(:previous_subscription) do
        create(
          :subscription,
          previous_subscription: initial_subscription,
          started_at: Time.zone.yesterday,
          external_id: 'sub_id',
          customer: customer,
          status: :terminated,
        )
      end

      let(:initial_subscription) do
        create(
          :subscription,
          started_at: Time.current.last_year,
          external_id: 'sub_id',
          status: :terminated,
          customer: customer,
        )
      end

      it 'returns the initial subscription started_at' do
        expect(subscription.initial_started_at.to_date).to eq(initial_subscription.started_at.to_date)
      end
    end
  end

  describe '#valid_external_id' do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization: organization) }
    let(:plan) { create(:plan) }
    let(:external_id) { SecureRandom.uuid }
    let(:subscription) do
      create(
        :active_subscription,
        plan: plan,
        customer: create(:customer, organization: organization),
      )
    end

    let(:new_subscription) do
      build(
        :active_subscription,
        plan: plan,
        external_id: external_id,
        customer: create(:customer, organization: organization),
      )
    end

    before { subscription }

    context 'when external_id is unique' do
      it 'does not raise validation error if external_id is unique' do
        expect(new_subscription).to be_valid
      end
    end

    context 'when external_id is NOT unique' do
      let(:external_id) { subscription.external_id }

      it 'raises validation error' do
        expect(new_subscription).not_to be_valid
      end
    end
  end

  describe '#downgrade_plan_date' do
    let(:subscription) { create(:subscription) }

    context 'without next subscription' do
      it 'returns nil' do
        expect(subscription.downgrade_plan_date).to be_nil
      end
    end

    context 'without pending next subscription' do
      it 'returns nil' do
        create(:subscription, previous_subscription: subscription, status: :active)
        expect(subscription.downgrade_plan_date).to be_nil
      end
    end

    it 'returns the date when the plan will be downgraded' do
      current_date = DateTime.parse('20 Jun 2022')
      create(:subscription, previous_subscription: subscription, status: :pending)

      travel_to(current_date) do
        expect(subscription.downgrade_plan_date).to eq(Date.parse('1 Jul 2022'))
      end
    end
  end

  describe '#fee_exists??' do
    let(:subscription) { create(:subscription) }
    let(:current_date) { Time.current.to_date }

    context 'without subscriptions fees that are created today' do
      before { create(:fee, subscription: subscription, created_at: Time.current - 2.days) }

      it 'returns false' do
        expect(subscription.fee_exists?(current_date)).to be false
      end
    end

    context 'with subscription fees that are created today' do
      before { create(:fee, subscription: subscription) }

      it 'returns true' do
        expect(subscription.fee_exists?(current_date)).to be true
      end
    end
  end

  describe '#starting_in_the_future?' do
    context 'when subscription is active' do
      let(:subscription) { create(:active_subscription) }

      it 'returns false' do
        expect(subscription.starting_in_the_future?).to be false
      end
    end

    context 'when subscription is pending and starting in the future' do
      let(:subscription) { create(:pending_subscription) }

      it 'returns true' do
        expect(subscription.starting_in_the_future?).to be true
      end
    end

    context 'when subscription is pending and downgraded' do
      let(:old_subscription) { create(:active_subscription) }
      let(:subscription) { create(:pending_subscription, previous_subscription: old_subscription) }

      it 'returns false' do
        expect(subscription.starting_in_the_future?).to be false
      end
    end
  end
end
