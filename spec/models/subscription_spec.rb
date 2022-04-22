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

      context 'when previous plan was more expersive' do
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
end
