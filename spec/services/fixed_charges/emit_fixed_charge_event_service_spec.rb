# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::EmitFixedChargeEventService, type: :service do
  subject(:emit_service) do
    described_class.new(
      subscription:,
      fixed_charge:,
      timestamp:
    )
  end

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charge) do
    create(
      :fixed_charge,
      organization:,
      plan:,
      add_on:,
      units: 10.0,
      pay_in_advance: false
    )
  end
  let(:timestamp) { Time.current }
  let(:customer) { create(:customer, organization:, billing_entity:) }
  let(:subscription) { create(:subscription, customer:, plan:, organization:, billing_entity:) }

  describe "#call" do
    subject(:result) { emit_service.call }

    it "returns a successful result with the created fixed charge event" do
      freeze_time do
        expect(result).to be_success
        expect(result.fixed_charge_event).to be_a(FixedChargeEvent)
        expect(result.fixed_charge_event).to have_attributes(
          organization:,
          subscription:,
          fixed_charge:,
          units: BigDecimal("10.0"),
          timestamp:
        )
      end
    end

    context "when fixed charge event creation fails" do
      let(:service_failure) do
        BaseResult.new.record_validation_failure!(record: fixed_charge)
      end

      before do
        allow(FixedChargeEvents::CreateService).to receive(:call).and_return(service_failure)
      end

      it "returns the failed result from the create service" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end
    end
  end
end
