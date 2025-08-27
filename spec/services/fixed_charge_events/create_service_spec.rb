# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedChargeEvents::CreateService, type: :service do
  subject(:create_service) do
    described_class.new(
      subscription:,
      fixed_charge:,
      units:,
      timestamp:
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charge) { create(:fixed_charge, organization:, plan:, add_on:) }
  let(:timestamp) { Time.current }
  let(:units) { 5.0 }

  describe "#call" do
    subject(:result) { create_service.call }

    it "creates a fixed charge event" do
      expect { create_service.call }
        .to change(FixedChargeEvent, :count).by(1)
    end

    it "returns a successful result with the created fixed charge event" do
      freeze_time do
        expect(result).to be_success
        expect(result.fixed_charge_event).to be_a(FixedChargeEvent)
        expect(result.fixed_charge_event).to have_attributes(
          organization:,
          subscription:,
          fixed_charge:,
          units: BigDecimal("5.0"),
          timestamp:
        )
      end
    end

    context "when units is nil" do
      let(:units) { nil }

      it "returns a validation error" do
        expect(result).to be_a_failure
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:units]).to include("is not a number")
      end
    end

    context "when units is negative" do
      let(:units) { -1.0 }

      it "returns a validation error" do
        expect(result).to be_a_failure
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:units]).to include("value_is_out_of_range")
      end
    end

    context "when required associations are missing" do
      let(:subscription) { nil }

      it "returns a validation error" do
        expect(result).to be_a_failure
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end
    end
  end
end
