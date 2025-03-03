# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Preview::CreditsService, type: :service do
  describe ".call" do
    subject(:result) { described_class.call(invoice:, terminated_subscription:) }

    let(:credits) { result.credits.map { |c| c.attributes.symbolize_keys } }

    let(:customer) { create(:customer) }
    let(:organization) { customer.organization }
    let(:invoice) { build(:invoice, customer:, organization:, total_amount_cents: 10_000) }

    let(:credit_notes) do
      create_pair(
        :credit_note,
        customer:,
        invoice: build(:invoice, customer:, organization:)
      )
    end

    let(:expected_credits_from_customer) do
      credit_notes.map do |note|
        hash_including(
          amount_cents: note.total_amount_cents,
          amount_currency: note.total_amount_currency
        )
      end
    end

    context "when terminated_subscription is present" do
      let(:plan) { create(:plan, organization:, pay_in_advance:, amount_cents: 10_000) }

      let(:subscription) do
        create(
          :subscription,
          organization:,
          customer:,
          plan:,
          subscription_at: Time.zone.parse("2025-02-01"),
          started_at: Time.zone.parse("2025-02-01")
        )
      end

      let(:terminated_subscription) do
        subscription.tap do |sub|
          sub.assign_attributes(
            status: :terminated,
            terminated_at: Time.zone.parse("15-02-2025")
          )
        end
      end

      before do
        BillSubscriptionJob.perform_now(
          [subscription],
          Time.zone.parse("2025-02-01").to_i,
          invoicing_reason: :subscription_starting
        )

        credit_notes
      end

      context "when subscription has a credit note" do
        let(:pay_in_advance) { true }

        let(:expected_credits_from_subscription) do
          [
            hash_including(
              amount_cents: 4643,
              amount_currency: "EUR"
            )
          ]
        end

        it "returns credits generated from subscription and customer credit notes" do
          expect(result).to be_success
          expect(credits).to match_array expected_credits_from_customer + expected_credits_from_subscription
        end
      end

      context "when subscription has no credit note" do
        let(:pay_in_advance) { false }

        it "returns credits generated from customer's credit notes" do
          expect(result).to be_success
          expect(credits).to match_array expected_credits_from_customer
        end
      end
    end

    context "when terminated_subscription is missing" do
      let(:terminated_subscription) { nil }

      before { credit_notes }

      it "returns credits generated from customer's credit notes" do
        expect(result).to be_success
        expect(credits).to match_array expected_credits_from_customer
      end
    end
  end
end
