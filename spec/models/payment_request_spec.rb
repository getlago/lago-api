# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequest, type: :model do
  subject(:payment_request) do
    described_class.new(
      organization:,
      customer:,
      payment_requestable: payable_group,
      email: Faker::Internet.email,
      amount_cents: Faker::Number.number(digits: 5),
      amount_currency: Faker::Currency.code
    )
  end

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }
  let(:payment) { create(:payment) }
  let(:payable_group) { create(:payable_group) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to have_many(:payments) }
  it { is_expected.to belong_to(:customer) }
  it { is_expected.to belong_to(:payment_requestable) }

  describe "Validations" do
    it "is valid with valid attributes" do
      expect(payment_request).to be_valid
    end

    it "is not valid without email" do
      payment_request.email = nil
      expect(payment_request).not_to be_valid
    end

    it "is not valid without amount_cents" do
      payment_request.amount_cents = nil
      expect(payment_request).not_to be_valid
    end

    it "is not valid without amount_currency" do
      payment_request.amount_currency = nil
      expect(payment_request).not_to be_valid
    end
  end

  describe "#invoices" do
    context "when payment_requestable is an invoice" do
      let(:invoice) { create(:invoice) }
      let(:payment_request) { create(:payment_request, payment_requestable: invoice) }

      it "returns an array with the invoice" do
        expect(payment_request.invoices).to eq([invoice])
      end
    end

    context "when payment_requestable is a payable_group" do
      let(:payable_group) { create(:payable_group) }
      let(:payment_request) { create(:payment_request, payment_requestable: payable_group) }

      it "returns the invoices from the payable_group" do
        invoice = create(:invoice, payable_group:)
        expect(payment_request.invoices).to eq([invoice])
      end
    end
  end
end
