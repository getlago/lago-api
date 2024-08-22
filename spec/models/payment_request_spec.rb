# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequest, type: :model do
  subject(:payment_request) do
    described_class.new(
      organization:,
      customer:,
      email: Faker::Internet.email,
      amount_cents: Faker::Number.number(digits: 5),
      amount_currency: Faker::Currency.code
    )
  end

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }
  let(:payment) { create(:payment) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to have_many(:applied_invoices).class_name("PaymentRequest::AppliedInvoice") }
  it { is_expected.to have_many(:invoices).through(:applied_invoices) }
  it { is_expected.to have_many(:payments) }

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:customer) }

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
end
