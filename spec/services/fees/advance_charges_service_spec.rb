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
          subscription: create_charge_fee(subscription: create(:subscription, organization:, customer:, plan:)),
          invoice_group: create_charge_fee(subscription: create(
            :subscription, organization:, customer:, plan:, external_id: subscription.external_id,
            status: :terminated, terminated_at: billing_at - 1.day
          ))
        }
      end

      before do
        charge
        create(:invoice_subscription, invoice:, subscription:)
        eligible_fee
        fee_without_charges_to_datetime
        excluded_fees
      end

      it "attaches only due succeeded fees for the invoice's subscriptions" do
        expect(result).to be_success
        expect(invoice.fees.reload).to match_array([eligible_fee, fee_without_charges_to_datetime])
        expect(excluded_fees.transform_values { |fee| fee.reload.invoice_id == invoice.id }).to eq(
          payment_status: false,
          succeeded_at: false,
          invoice: false,
          charges_to_datetime: false,
          subscription: false,
          invoice_group: false
        )
      end

      it "attaches the eligible fees in a single database update" do
        statements = capture_sql { result }

        expect(statements.grep(/\AUPDATE "fees"/).size).to eq(1)
        expect(invoice.fees.reload).to match_array([eligible_fee, fee_without_charges_to_datetime])
      end

      context "when the invoice groups a predecessor on a different plan" do
        let(:subscription) do
          create(:subscription, organization:, customer:, plan:, status: :terminated,
            terminated_at: billing_at - 1.day)
        end
        let(:current_subscription) do
          create(:subscription, organization:, customer:, external_id: subscription.external_id)
        end
        let(:billing_contexts) { [Billing::Context.from(subscription: current_subscription)] }

        it "uses the original periodic boundary and the predecessor's regrouping charge" do
          expect(result).to be_success
          expect(invoice.fees.reload).to match_array([eligible_fee, fee_without_charges_to_datetime])
          expect(excluded_fees[:charges_to_datetime].reload.invoice_id).to be_nil
        end
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
