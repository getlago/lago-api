# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::FixedChargeUnitOverrideService, type: :service do
  subject(:service) { described_class.new(subscription:, fixed_charge:, units:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charge) { create(:fixed_charge, plan:, add_on:, organization:) }
  let(:units) { 5 }

  describe "#call" do
    context "when success" do
      it "returns a fixed charge unit override" do
        result = service.call

        expect(result).to be_success
        expect(result.fixed_charge_unit_override).to be_a(SubscriptionFixedChargeUnitsOverride)
      end

      it "builds the fixed charge unit override with correct attributes" do
        result = service.call
        override = result.fixed_charge_unit_override

        expect(override.organization).to eq(subscription.organization)
        expect(override.billing_entity).to eq(subscription.billing_entity)
        expect(override.subscription).to eq(subscription)
        expect(override.fixed_charge).to eq(fixed_charge)
        expect(override.units).to eq(units)
      end
    end

    context "when validation fails" do
      context "with zero units" do
        let(:units) { 0 }

        it "sets zero units" do
          result = service.call
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:units]).to eq(["value_is_out_of_range"])
        end
      end

      context "with negative units" do
        let(:units) { -1 }

        it "sets zero units" do
          result = service.call
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:units]).to eq(["value_is_out_of_range"])
        end
      end

      context "when subscription is nil" do
        let(:subscription) { nil }

        it "returns a not found failure" do
          result = service.call
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("subscription")
        end
      end
    end
  end
end
