# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::UpdateAmountService, type: :service do
  subject(:update_service) { described_class.new(plan:, amount_cents:, expected_amount_cents:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:, amount_cents: 111) }
  let(:amount_cents) { 222 }
  let(:expected_amount_cents) { 111 }

  before { plan }

  describe '#call' do
    it 'updates the subscription fee' do
      update_service.call

      expect(plan.reload.amount_cents).to eq(222)
    end

    context 'when plan is not found' do
      let(:plan) { nil }

      it 'returns an error' do
        result = update_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('plan_not_found')
        end
      end
    end

    context 'when the expected_amount_cents does not match the plan amount_cents' do
      let(:expected_amount_cents) { 10 }

      it 'does not update the plan' do
        result = update_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.plan.reload.amount_cents).to eq(111)
        end
      end
    end

    context "when there are pending subscriptions which are not relevant after the amount cents increase", :aggregate_failures do
      let(:original_plan) { create(:plan, organization:, amount_cents: expected_amount_cents) }
      let(:subscription) { create(:subscription, plan: original_plan) }
      let(:pending_subscription) do
        create(:subscription, plan:, status: :pending, previous_subscription_id: subscription.id)
      end
      let(:plan_upgrade_result) { BaseService::Result.new }

      before do
        allow(Subscriptions::PlanUpgradeService)
          .to receive(:call)
          .and_return(plan_upgrade_result)

        pending_subscription
      end

      it "upgrades subscription plan" do
        update_service.call

        expect(Subscriptions::PlanUpgradeService).to have_received(:call)
      end

      context "when pending subscription does not have a previous one" do
        let(:pending_subscription) do
          create(:subscription, plan:, status: :pending, previous_subscription_id: nil)
        end

        it "does not upgrade it" do
          update_service.call

          expect(Subscriptions::PlanUpgradeService).not_to have_received(:call)
        end
      end

      context "when subscription upgrade fails" do
        let(:plan_upgrade_result) do
          BaseService::Result.new.validation_failure!(
            errors: {billing_time: ["value_is_invalid"]}
          )
        end

        it "returns an error" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq({billing_time: ["value_is_invalid"]})
        end
      end
    end
  end
end
