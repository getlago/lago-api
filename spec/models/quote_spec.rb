# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quote, type: :model do
  subject(:quote) { build(:quote) }

  describe "enums" do
    it "defines the expected enums" do
      expect(subject).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(Quote::STATUSES)

      expect(subject).to define_enum_for(:order_type)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(Quote::ORDER_TYPES)
        .without_instance_methods
    end
  end

  describe "associations" do
    it "defines the expected associations" do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:customer)
      expect(subject).to belong_to(:subscription).optional
      expect(subject).to have_many(:quote_owners).dependent(:destroy)
      expect(subject).to have_many(:owners).through(:quote_owners).source(:user).class_name("User")
    end

    it "loads a discarded customer" do
      customer = create(:customer)
      quote = create(:quote, organization: customer.organization, customer:)
      customer.discard!

      expect(quote.reload.customer).to eq(customer)
    end
  end

  describe "#number" do
    it "is set to QT-<year>-<4-digit-seq> on save when blank" do
      org = create(:organization)
      customer = create(:customer, organization: org)
      q = Quote.new(organization: org, customer:, status: :draft, order_type: :subscription_creation, version: 1)
      q.save!
      expect(q.number).to match(/\AQT-\d{4}-\d{4}\z/)
    end

    it "does not overwrite an existing number" do
      q = create(:quote, number: "QT-2099-9999")
      q.save!
      expect(q.number).to eq("QT-2099-9999")
    end
  end
end
