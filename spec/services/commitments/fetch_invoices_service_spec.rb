# frozen_string_literal: true

require "rails_helper"

RSpec.describe Commitments::FetchInvoicesService do
  let(:commitment) { create(:commitment, plan:) }
  let(:plan) { create(:plan, pay_in_advance:) }
  let(:subscription) { create(:subscription, plan:) }
  let(:invoice_subscription) { create(:invoice_subscription, subscription:) }
  let(:pay_in_advance) { false }

  describe ".new_instance" do
    subject(:instance) { described_class.new_instance(commitment:, invoice_subscription:) }

    context "when the plan is paid in arrears" do
      let(:pay_in_advance) { false }

      it "returns an in arrears fetch invoices service" do
        expect(instance).to be_a(Commitments::Minimum::InArrears::FetchInvoicesService)
      end
    end

    context "when the plan is paid in advance" do
      let(:pay_in_advance) { true }

      it "returns an in advance fetch invoices service" do
        expect(instance).to be_a(Commitments::Minimum::InAdvance::FetchInvoicesService)
      end
    end
  end

  describe "#call" do
    subject(:result) { described_class.new_instance(commitment:, invoice_subscription:).call }

    context "when the plan is paid in arrears" do
      let(:pay_in_advance) { false }

      it "returns the invoice subscription invoice" do
        expect(result).to be_success
        expect(result.invoices).to eq([invoice_subscription.invoice])
      end
    end

    context "when the plan is paid in advance" do
      let(:pay_in_advance) { true }

      it "returns the invoice subscription invoice" do
        expect(result).to be_success
        expect(result.invoices).to eq([invoice_subscription.invoice])
      end
    end
  end
end
