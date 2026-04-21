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

      expect(subject).to define_enum_for(:void_reason)
        .backed_by_column_of_type(:enum)
        .with_values(Quote::VOID_REASONS)
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
  end

  describe "customer association" do
    it "loads a discarded customer" do
      customer = create(:customer)
      quote = create(:quote, organization: customer.organization, customer:)
      customer.discard!

      expect(quote.reload.customer).to eq(customer)
    end
  end

  describe "sequential_id" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:quote) { build(:quote, organization:, customer:) }

    it "assigns a sequential_id when blank" do
      quote.save!

      expect(quote).to be_valid
      expect(quote.sequential_id).to eq(1)
    end

    context "when sequential_id is present" do
      before { quote.sequential_id = 3 }

      it "does not replace the sequential_id" do
        quote.save!

        expect(quote).to be_valid
        expect(quote.sequential_id).to eq(3)
      end
    end

    context "when another quote already exists in the organization" do
      before { create(:quote, organization:, sequential_id: 5) }

      it "takes the next available id" do
        quote.save!

        expect(quote).to be_valid
        expect(quote.sequential_id).to eq(6)
      end
    end

    context "with quotes in another organization" do
      before { create(:quote, sequential_id: 1) }

      it "scopes the sequence to the organization" do
        quote.save!

        expect(quote).to be_valid
        expect(quote.sequential_id).to eq(1)
      end
    end
  end

  describe "number" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:quote) { build(:quote, organization:, customer:) }

    it "is set to QT-<year>-<4-digit-seq> on save when blank" do
      quote.save!

      expect(quote.number).to match(/\AQT-\d{4}-\d{4}\z/)
    end

    it "uses the year from created_at rather than the current time" do
      travel_to(Time.zone.local(2025, 6, 1)) { quote.save! }

      travel_to(Time.zone.local(2026, 3, 1)) do
        quote.update!(status: :approved)
        expect(quote.number).to start_with("QT-2025-")
      end
    end

    it "does not overwrite an existing number" do
      persisted = create(:quote, organization:, customer:, number: "QT-2099-9999")
      persisted.save!

      expect(persisted.number).to eq("QT-2099-9999")
    end
  end

  describe "status" do
    it "defaults to draft" do
      expect(described_class.new.status).to eq("draft")
    end
  end
end
