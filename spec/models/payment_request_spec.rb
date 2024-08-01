# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequest, type: :model do
  subject(:payment_request) do
    described_class.new(
      customer:,
      payment_requestable: payable_group,
      email: Faker::Internet.email,
      amount_cents: Faker::Number.number(digits: 5),
      amount_currency: Faker::Currency.code
    )
  end

  let(:customer) { create(:customer) }
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
end
