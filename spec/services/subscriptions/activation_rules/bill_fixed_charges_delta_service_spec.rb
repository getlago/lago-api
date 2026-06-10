# frozen_string_literal: true

require "rails_helper"

describe Subscriptions::ActivationRules::BillFixedChargesDeltaService do
  subject(:result) { described_class.call(subscription:, invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:started_at) { Time.current.change(usec: 0) - 20.days }
  let(:subscription) { create(:subscription, :incomplete, organization:, customer:, plan:, started_at:) }
  let(:invoice) { create(:invoice, organization:, customer:) }

  describe "#call" do
    context "when the subscription has no pay-in-advance fixed charges" do
      before { create(:fixed_charge, plan:, organization:) }

      it "does not enqueued an Invoices::CreatePayInAdvanceFixedChargesJob" do
        expect { result }.not_to have_enqueued_job(Invoices::CreatePayInAdvanceFixedChargesJob)
      end
    end

    context "when the only event is the creation event at started_at + 1.second" do
      let(:fixed_charge) { create(:fixed_charge, :pay_in_advance, plan:, organization:) }

      before { create(:fixed_charge_event, subscription:, fixed_charge:, timestamp: started_at + 1.second) }

      it "does not enqueued an Invoices::CreatePayInAdvanceFixedChargesJob" do
        expect { result }.not_to have_enqueued_job(Invoices::CreatePayInAdvanceFixedChargesJob)
      end
    end

    context "when there are events during the incomplete window" do
      let(:fixed_charge) { create(:fixed_charge, :pay_in_advance, plan:, organization:) }
      let(:event_timestamp) { started_at + 10.days }

      before do
        create(:fixed_charge_event, subscription:, fixed_charge:, timestamp: started_at + 1.second)
        create(:fixed_charge_event, subscription:, fixed_charge:, timestamp: event_timestamp)
      end

      it "enqueues one Invoices::CreatePayInAdvanceFixedChargesJob for the delta timestamp" do
        expect { result }.to have_enqueued_job(Invoices::CreatePayInAdvanceFixedChargesJob)
          .with(subscription, event_timestamp.to_i).exactly(:once)
      end

      context "when several events share a timestamp" do
        let(:other_fixed_charge) { create(:fixed_charge, :pay_in_advance, plan:, organization:) }

        before { create(:fixed_charge_event, subscription:, fixed_charge: other_fixed_charge, timestamp: event_timestamp) }

        it "groups by timestamp into a single Invoices::CreatePayInAdvanceFixedChargesJob" do
          expect { result }.to have_enqueued_job(Invoices::CreatePayInAdvanceFixedChargesJob)
            .with(subscription, event_timestamp.to_i).exactly(:once)
        end
      end

      context "when there are two distinct plan-update timestamps" do
        before { create(:fixed_charge_event, subscription:, fixed_charge:, timestamp: started_at + 15.days) }

        it "enqueues one Invoices::CreatePayInAdvanceFixedChargesJob per distinct timestamp" do
          expect { result }.to have_enqueued_job(Invoices::CreatePayInAdvanceFixedChargesJob).exactly(2).times
        end
      end
    end
  end
end
