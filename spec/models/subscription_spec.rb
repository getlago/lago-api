# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscription, type: :model do
  subject(:subscription) { create(:subscription, plan:) }

  let(:plan) { create(:plan) }

  it_behaves_like 'paper_trail traceable'

  it { is_expected.to have_many(:daily_usages) }
  it { is_expected.to have_many(:integration_resources) }
  it { is_expected.to have_one(:lifetime_usage) }

  describe '#upgraded?' do
    let(:previous_subscription) { nil }
    let(:subscription) do
      create(:subscription, previous_subscription:, plan:)
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
      create(:subscription, previous_subscription:, plan:)
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
          :subscription,
          previous_subscription:,
          started_at: Time.zone.yesterday,
          plan:,
          external_id: 'sub_id',
          customer: previous_subscription.customer
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

  describe '#trial_end_datetime' do
    let(:plan) { create(:plan, trial_period: 3) }
    let(:started_at) { subscription.initial_started_at }

    it 'returns the trial end datetime' do
      trial_end_datetime = subscription.trial_end_datetime

      aggregate_failures do
        expect(trial_end_datetime).to be_present
        expect(trial_end_datetime).to eq(started_at + 3.days)
      end
    end

    context 'when plan has no trial' do
      let(:plan) { create(:plan) }

      it 'returns nil' do
        expect(subscription.trial_end_datetime).to be_nil
      end
    end

    context 'with a previous subscription' do
      let(:subscription) do
        create(
          :subscription,
          previous_subscription:,
          started_at: Time.zone.yesterday,
          plan:,
          external_id: 'sub_id',
          customer: previous_subscription.customer
        )
      end
      let(:previous_subscription) do
        create(:subscription, started_at: Time.current.last_month, external_id: 'sub_id', status: :terminated)
      end

      it 'takes previous subscription started_at into account' do
        trial_end_datetime = subscription.trial_end_datetime

        aggregate_failures do
          expect(trial_end_datetime).to be_present
          expect(trial_end_datetime).to eq(started_at + 3.days)
        end
      end
    end
  end

  describe '#in_trial_period?' do
    context 'when plan has no trial' do
      it { expect(subscription.in_trial_period?).to be false }
    end

    context 'when subscription is in trial' do
      let(:subscription) { create(:subscription, plan:, started_at: 5.days.ago) }
      let(:plan) { create(:plan, trial_period: 10) }

      it { expect(subscription.in_trial_period?).to be true }
    end

    context 'when subscription trial has ended' do
      let(:subscription) { create(:subscription, plan:, started_at: 5.days.ago) }
      let(:plan) { create(:plan, trial_period: 2) }

      it { expect(subscription.in_trial_period?).to be false }
    end
  end

  describe '#initial_started_at' do
    let(:customer) { create(:customer) }
    let(:subscription) do
      create(
        :subscription,
        previous_subscription:,
        started_at: Time.zone.yesterday,
        external_id: 'sub_id',
        customer:
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
          customer:
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
          customer:,
          status: :terminated
        )
      end

      let(:initial_subscription) do
        create(
          :subscription,
          started_at: Time.current.last_year,
          external_id: 'sub_id',
          status: :terminated,
          customer:
        )
      end

      it 'returns the initial subscription started_at' do
        expect(subscription.initial_started_at.to_date).to eq(initial_subscription.started_at.to_date)
      end
    end
  end

  describe '#valid_external_id' do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:external_id) { SecureRandom.uuid }
    let(:subscription) do
      create(
        :subscription,
        plan:,
        customer: create(:customer, organization:)
      )
    end

    let(:new_subscription) do
      build(
        :subscription,
        plan:,
        external_id:,
        customer: create(:customer, organization:)
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

  describe '#starting_in_the_future?' do
    context 'when subscription is active' do
      let(:subscription) { create(:subscription) }

      it 'returns false' do
        expect(subscription.starting_in_the_future?).to be false
      end
    end

    context 'when subscription is pending and starting in the future' do
      let(:subscription) { create(:subscription, :pending) }

      it 'returns true' do
        expect(subscription.starting_in_the_future?).to be true
      end
    end

    context 'when subscription is pending and downgraded' do
      let(:old_subscription) { create(:subscription) }
      let(:subscription) { create(:subscription, :pending, previous_subscription: old_subscription) }

      it 'returns false' do
        expect(subscription.starting_in_the_future?).to be false
      end
    end
  end

  describe '#display_name' do
    let(:subscription) { build(:subscription, name: subscription_name, plan:) }
    let(:subscription_name) { 'some_name' }
    let(:plan) { create(:plan, name: 'some_plan_name') }

    it { expect(subscription.display_name).to eq('some_name') }

    context 'when name is empty' do
      let(:subscription_name) { nil }

      it 'returns the plan name' do
        expect(subscription.display_name).to eq('some_plan_name')
      end
    end
  end

  describe '#invoice_name' do
    subject(:subscription_invoice_name) { subscription.invoice_name }

    let(:subscription) { build_stubbed(:subscription, plan:, name:) }

    context 'when plan invoice display name is blank' do
      let(:plan) { build_stubbed(:plan, invoice_display_name: [nil, ''].sample) }

      context 'when subscription name is blank' do
        let(:name) { [nil, ''].sample }

        it 'returns plan name' do
          expect(subscription_invoice_name).to eq(plan.name)
        end
      end

      context 'when subscription name is present' do
        let(:name) { Faker::TvShows::GameOfThrones.characters }

        it 'returns subscription name' do
          expect(subscription_invoice_name).to eq(subscription.name)
        end
      end
    end

    context 'when plan invoice display name is present' do
      let(:plan) { build_stubbed(:plan) }

      context 'when subscription name is blank' do
        let(:name) { [nil, ''].sample }

        it 'returns plan invoice display name' do
          expect(subscription_invoice_name).to eq(plan.invoice_display_name)
        end
      end

      context 'when subscription name is present' do
        let(:name) { Faker::TvShows::GameOfThrones.characters }

        it 'returns subscription name' do
          expect(subscription_invoice_name).to eq(subscription.name)
        end
      end
    end
  end

  describe '#should_sync_crm_subscription?' do
    subject(:method_call) { subscription.should_sync_crm_subscription? }

    let(:subscription) { create(:subscription, customer:) }
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }

    context 'without integration crm customer' do
      it 'returns false' do
        expect(method_call).to eq(false)
      end
    end

    context 'with integration crm customer' do
      let(:integration_customer) { create(:hubspot_customer, integration:, customer:) }
      let(:integration) { create(:hubspot_integration, organization:, sync_subscriptions:) }

      before { integration_customer }

      context 'when sync subscriptions is true' do
        let(:sync_subscriptions) { true }

        it 'returns true' do
          expect(method_call).to eq(true)
        end
      end

      context 'when sync subscriptions is false' do
        let(:sync_subscriptions) { false }

        it 'returns false' do
          expect(method_call).to eq(false)
        end
      end
    end
  end

  describe '.date_diff_with_timezone' do
    let(:from_datetime) { Time.zone.parse('2023-08-31T23:10:00') }
    let(:to_datetime) { Time.zone.parse('2023-09-30T22:59:59') }
    let(:customer) { create(:customer, timezone:) }
    let(:terminated_at) { nil }
    let(:timezone) { 'Europe/Paris' }

    let(:subscription) do
      create(
        :subscription,
        plan:,
        customer:,
        terminated_at:
      )
    end

    let(:result) do
      subscription.date_diff_with_timezone(from_datetime, to_datetime)
    end

    it 'returns the number of days between the two datetime' do
      expect(result).to eq(30)
    end

    context 'with terminated and upgraded subscription' do
      let(:terminated_at) { Time.zone.parse('2023-09-30T22:59:59') }
      let(:new_subscription) do
        create(
          :subscription,
          plan:,
          customer:,
          previous_subscription_id: subscription.id
        )
      end

      before do
        subscription.terminated!
        new_subscription
      end

      it 'takes the daylight saving time into account' do
        expect(result).to eq(29)
      end
    end
  end

  describe '#mark_as_active!' do
    subject(:subscription) { create(:subscription, status: :pending) }

    it 'changes the status to active' do
      expect { subscription.mark_as_active! }
        .to change(subscription, :status).from('pending').to('active')

      expect(subscription.started_at).to be_present
      expect(subscription.lifetime_usage).to be_present
    end

    context 'with a previous subscription' do
      subject(:subscription) { create(:subscription, status: :pending, previous_subscription:) }

      let(:previous_subscription) { create(:subscription, :terminated) }
      let(:lifetime_usage) { create(:lifetime_usage, subscription: previous_subscription) }

      before { lifetime_usage }

      it 'changes the status to active' do
        expect { subscription.mark_as_active! }
          .to change(subscription, :status).from('pending').to('active')

        expect(lifetime_usage.reload.subscription).to eq(subscription)
      end
    end
  end

  describe '#terminated_at?' do
    context 'when subscription is terminated before the timestamp' do
      it 'returns true' do
        subscription = build(:subscription, :terminated, terminated_at: 2.days.ago)
        expect(subscription.terminated_at?(1.day.ago)).to be true
      end
    end

    context 'when subscription is terminated after the timestamp' do
      it 'returns false' do
        subscription = build(:subscription, :terminated, terminated_at: 1.day.from_now)
        expect(subscription.terminated_at?(2.days.ago)).to be false
      end
    end

    context 'when subscription is not terminated' do
      it 'returns false' do
        subscription = build(:subscription)
        expect(subscription.terminated_at?(1.day.ago)).to be false
      end
    end
  end
end
