# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::RefundPaymentJob do
  subject(:perform_job) { described_class.perform_now(payment, reason:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:payment) { create(:payment, payable: invoice, organization:, customer:) }
  let(:reason) { :subscription_activation_expired }

  before do
    allow(PaymentProviders::RefundPaymentService).to receive(:call!)
  end

  it "delegates to RefundPaymentService with payment and reason" do
    perform_job

    expect(PaymentProviders::RefundPaymentService).to have_received(:call!).with(payment:, reason:)
  end

  context "without a reason" do
    subject(:perform_job) { described_class.perform_now(payment) }

    it "delegates with reason: nil" do
      perform_job

      expect(PaymentProviders::RefundPaymentService).to have_received(:call!).with(payment:, reason: nil)
    end
  end
end
