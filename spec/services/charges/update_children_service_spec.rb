# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::UpdateChildrenService do
  subject(:update_service) do
    described_class.new(
      charge:,
      params:,
      old_parent_attrs:,
      old_parent_applied_pricing_unit_attrs:,
      child_ids:
    )
  end

  # Not let_it_be: the concurrent examples read these records from other database connections.
  let(:organization) { create_default(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:child_plan) { create(:plan, organization:, parent_id: plan.id) }
  let(:old_parent_attrs) { charge&.attributes }
  let(:charge_parent_id) { charge.id }
  let(:child_ids) { [child_charge&.id] }
  let(:child_charge) do
    create(
      :standard_charge,
      plan_id: child_plan.id,
      parent_id: charge_parent_id,
      billable_metric_id: billable_metric.id,
      properties: {amount: "300"}
    )
  end
  let(:params) do
    {
      id: charge&.id,
      billable_metric_id: billable_metric.id,
      charge_model: "standard",
      pay_in_advance: true,
      prorated: true,
      invoiceable: false,
      properties: {
        amount: "400"
      },
      applied_pricing_unit: {conversion_rate: 2.5}
      # Filter cascade is no longer routed through this service — it goes
      # via per-filter ChargeFilters::CascadeJob (see
      # Charges::CascadeUpdatable / Plans::UpdateService).
    }
  end
  let(:old_parent_applied_pricing_unit_attrs) { charge&.applied_pricing_unit&.attributes }
  let(:charge) do
    create(
      :standard_charge,
      plan:,
      billable_metric:,
      amount_currency: "USD",
      properties: {
        amount: "300"
      }
    )
  end

  before do
    charge && create(:applied_pricing_unit, pricing_unitable: charge, conversion_rate: 1.1)
    child_charge && create(:applied_pricing_unit, pricing_unitable: child_charge, conversion_rate: 1.1)
  end

  describe "#call" do
    context "when charge is not found" do
      let(:charge) { nil }
      let(:child_charge) { nil }

      it "returns an empty result" do
        result = update_service.call

        expect(result).to be_success
        expect(result.charge).to be_nil
      end
    end

    context "when charge has children that has not been modified" do
      it "cascades charge-level changes to the child" do
        update_service.call

        expect(child_charge.reload).to have_attributes(
          properties: {"amount" => "400"}
        )
        expect(child_charge.applied_pricing_unit.conversion_rate).to eq 2.5
      end

      it "does not touch plan" do
        freeze_time do
          expect { update_service.call }.not_to change { child_plan.reload.updated_at }
        end
      end

      it "does not cascade filters via this service" do
        # Filters are cascaded via ChargeFilters::CascadeJob, not here.
        allow(ChargeFilters::CreateOrUpdateBatchService).to receive(:call)

        update_service.call

        expect(ChargeFilters::CreateOrUpdateBatchService).not_to have_received(:call)
      end
    end

    context "when charge has children that has been modified" do
      let(:child_charge) do
        create(
          :standard_charge,
          plan_id: child_plan.id,
          parent_id: charge_parent_id,
          billable_metric_id: billable_metric.id,
          properties: {amount: "500"}
        )
      end

      it "does not update charge properties" do
        update_service.call

        expect(child_charge.reload).to have_attributes(
          properties: {"amount" => "500"}
        )
      end
    end

    context "when charge has no children" do
      let(:child_charge) do
        create(
          :standard_charge,
          plan_id: child_plan.id,
          parent_id: nil,
          billable_metric_id: billable_metric.id,
          properties: {amount: "300"}
        )
      end

      before do
        allow(Charges::UpdateService).to receive(:call!).and_call_original
      end

      it "does not call the update service" do
        update_service.call

        expect(Charges::UpdateService).not_to have_received(:call!)
      end

      it "does not update charge properties" do
        update_service.call

        expect(child_charge.reload).to have_attributes(
          properties: {"amount" => "300"}
        )
      end
    end

    context "when another batch is updating a child concurrently", transaction: false do
      let(:cascade_args) { {charge:, params:, old_parent_attrs:, old_parent_applied_pricing_unit_attrs:} }
      let(:next_cascade_args) do
        cascade_args.merge(
          params: params.merge(properties: {amount: "500"}),
          old_parent_attrs: old_parent_attrs.merge("properties" => {"amount" => "400"}),
          child_ids: [child_charge.id]
        )
      end
      let(:sibling_charge) do
        create(
          :standard_charge,
          plan: create(:plan, organization:, parent_id: plan.id),
          parent_id: charge.id,
          billable_metric:,
          properties: {amount: "300"}
        )
      end
      let(:update_started) { Queue.new }
      let(:resume_update) { Queue.new }

      before do
        pause_token = Queue.new
        pause_token << true
        started = update_started
        resume = resume_update

        allow(Charges::UpdateService).to receive(:call!).and_wrap_original do |original, **kwargs|
          if pause_token.pop(timeout: 0)
            started << true
            resume.pop(timeout: 10)
          end

          original.call(**kwargs)
        end
      end

      def call_in_thread(**args)
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection { described_class.call(**args) }
        end
      end

      it "does not wait for another batch of the same cascade" do
        sibling_batch = call_in_thread(**cascade_args, child_ids: [sibling_charge.id])
        update_started.pop(timeout: 10)

        expect(described_class.call(**cascade_args, child_ids: [child_charge.id])).to be_success
        expect(child_charge.reload.properties).to eq("amount" => "400")

        resume_update << true

        expect(sibling_batch.value).to be_success
        expect(sibling_charge.reload.properties).to eq("amount" => "400")
      end

      it "does not update the child while another cascade of the same parent holds it" do
        stub_const("#{described_class}::LOCK_TIMEOUT_SECONDS", 0)

        previous_cascade = call_in_thread(**cascade_args, child_ids: [child_charge.id])
        update_started.pop(timeout: 10)

        expect { described_class.call(**next_cascade_args) }.to raise_error(WithAdvisoryLock::FailedToAcquireLock)

        resume_update << true

        expect(previous_cascade.value).to be_success
        expect(child_charge.reload.properties).to eq("amount" => "400")
        expect(described_class.call(**next_cascade_args)).to be_success
        expect(child_charge.reload.properties).to eq("amount" => "500")
      end

      it "applies a cascade that waited for the lock on top of the previous one" do
        previous_cascade = call_in_thread(**cascade_args, child_ids: [child_charge.id])
        update_started.pop(timeout: 10)
        next_cascade = call_in_thread(**next_cascade_args)
        sleep 0.5

        resume_update << true

        expect([previous_cascade.value, next_cascade.value]).to all(be_success)
        expect(child_charge.reload.properties).to eq("amount" => "500")
      end
    end
  end
end
