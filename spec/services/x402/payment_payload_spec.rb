# frozen_string_literal: true

require "rails_helper"

describe X402::PaymentPayload do
  subject(:payment_payload) { described_class.new(payment:, payment_requirements:) }

  include_context "with an x402 payment"

  let(:payment) { x402_evm_payment }
  let(:payment_requirements) { x402_evm_requirements }

  it do
    expect(payment_payload).to have_attributes(
      x402_version: 2,
      scheme: "exact",
      network: "eip155:84532",
      asset: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
      pay_to: "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5",
      amount: 1000,
      max_timeout_seconds: 60,
      family: :evm,
      from: "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2",
      to: "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5",
      value: 1000,
      valid_before: 1_789_649_331,
      transaction: nil
    )
  end

  it "returns the given payment and requirements" do
    expect(payment_payload.payment).to be(payment)
    expect(payment_payload.payment_requirements).to be(payment_requirements)
  end

  context "with symbol keys" do
    let(:payment) { x402_evm_payment.deep_symbolize_keys }
    let(:payment_requirements) { x402_evm_requirements.deep_symbolize_keys }

    it do
      expect(payment_payload).to have_attributes(
        x402_version: 2,
        scheme: "exact",
        network: "eip155:84532",
        pay_to: "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5",
        amount: 1000,
        max_timeout_seconds: 60,
        family: :evm,
        from: "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2",
        value: 1000,
        valid_before: 1_789_649_331
      )
    end
  end

  context "with a Solana payment" do
    let(:payment) { x402_svm_payment }
    let(:payment_requirements) { x402_svm_requirements }

    it do
      expect(payment_payload).to have_attributes(
        family: :svm,
        transaction: x402_svm_payment["payload"]["transaction"],
        from: nil,
        to: nil,
        value: nil,
        valid_before: nil
      )
    end
  end

  context "with an unknown network" do
    let(:payment_requirements) { x402_evm_requirements.merge("network" => "eip155:1") }

    it { expect(payment_payload.family).to be_nil }
  end

  context "when the payment is not a hash" do
    let(:payment) { "payment" }

    it { expect(payment_payload).to have_attributes(x402_version: nil, from: nil, transaction: nil) }
  end

  context "when the requirements are not a hash" do
    let(:payment_requirements) { "requirements" }

    it { expect(payment_payload).to have_attributes(network: nil, amount: nil) }
  end

  context "when the payload is not an object" do
    let(:payment) { x402_evm_payment.merge("payload" => "x") }

    it { expect(payment_payload).to have_attributes(authorization: {}, from: nil) }
  end

  ["1.5", "-1", nil].each do |amount|
    context "with the amount #{amount.inspect}" do
      let(:payment_requirements) { x402_evm_requirements.merge("amount" => amount) }

      it { expect(payment_payload.amount).to be_nil }
    end
  end

  ["60", 60.0].each do |timeout|
    context "with the max timeout #{timeout.inspect}" do
      let(:payment_requirements) { x402_evm_requirements.merge("maxTimeoutSeconds" => timeout) }

      it { expect(payment_payload.max_timeout_seconds).to be_nil }
    end
  end
end
