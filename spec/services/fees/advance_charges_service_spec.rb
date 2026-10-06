# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::AdvanceChargesService do
  describe ".call" do
    subject(:result) do
      described_class.call(invoice:, billing_contexts:, billing_at:)
    end

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:invoice) { create(:invoice, organization:, customer:) }
    let(:billing_at) { Time.zone.parse("2026-09-30 23:59:59") }

    context "with charge fees" do
      let(:plan) { create(:plan, organization:) }
      let(:subscription) { create(:subscription, organization:, customer:, plan:) }
      let(:billing_contexts) { [Billing::Context.from(subscription:)] }
      let(:charge) do
        create(
          :standard_charge,
          plan:,
          pay_in_advance: true,
          invoiceable: false,
          regroup_paid_fees: :invoice
        )
      end
      let(:eligible_properties) { {"charges_to_datetime" => (billing_at - 1.day).iso8601(6)} }
      let(:eligible_fee) do
        create_charge_fee(properties: eligible_properties)
      end
      let(:fee_without_charges_to_datetime) do
        create_charge_fee(properties: {})
      end
      let(:excluded_fees) do
        {
          payment_status: create_charge_fee(payment_status: :failed, succeeded_at: nil),
          succeeded_at: create_charge_fee(succeeded_at: billing_at + 1.second),
          invoice: create_charge_fee(invoice: create(:invoice, organization:, customer:)),
          charges_to_datetime: create_charge_fee(
            properties: {"charges_to_datetime" => (billing_at + 1.second).iso8601(6)}
          ),
          subscription: create_charge_fee(subscription: create(:subscription, organization:, customer:, plan:))
        }
      end

      before do
        charge
        eligible_fee
        fee_without_charges_to_datetime
        excluded_fees
      end

      it "attaches only due succeeded fees for the supplied subscriptions" do
        expect(result).to be_success
        expect(invoice.fees.reload).to match_array([eligible_fee, fee_without_charges_to_datetime])
        expect(excluded_fees.transform_values { |fee| fee.reload.invoice_id == invoice.id }).to eq(
          payment_status: false,
          succeeded_at: false,
          invoice: false,
          charges_to_datetime: false,
          subscription: false
        )
      end

      context "when the charge does not regroup paid fees" do
        let(:charge) do
          create(
            :standard_charge,
            plan:,
            pay_in_advance: true,
            invoiceable: false,
            regroup_paid_fees: nil
          )
        end

        it "leaves the fees unattached" do
          expect(result).to be_success
          expect(invoice.fees.reload).to be_empty
          expect(eligible_fee.reload.invoice_id).to be_nil
        end
      end
    end

    def create_charge_fee(**attributes)
      create(
        :charge_fee,
        :succeeded,
        invoice: nil,
        organization:,
        subscription:,
        charge:,
        succeeded_at: billing_at - 1.second,
        **attributes
      )
    end
  end
end
