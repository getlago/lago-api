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

      expect(subject).to define_enum_for(:void_reason)
        .without_instance_methods
        .with_values(Quote::VOID_REASONS)

      expect(subject).to define_enum_for(:order_type)
        .without_instance_methods
        .validating
        .with_values(Quote::ORDER_TYPES)

      expect(subject).to define_enum_for(:execution_mode)
        .without_instance_methods
        .with_values(Quote::EXECUTION_MODES)

      expect(subject).to define_enum_for(:backdated_billing)
        .without_instance_methods
        .with_values(Quote::BACKDATED_BILLING_OPTIONS)
    end
  end

  describe "associations" do
    it "defines the expected associations" do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:customer)
      expect(subject).to have_many(:quote_owners).dependent(:destroy)
      expect(subject).to have_many(:owners).through(:quote_owners).source(:user).class_name("User")
    end
  end

  describe "validations" do
    describe "share_token validation" do
      it "requires share_token when draft" do
        q = create(:quote)
        q.share_token = nil
        expect(q).not_to be_valid
        expect(q.errors[:share_token]).to include("value_is_mandatory")
      end

      it "requires share_token when approved" do
        q = create(:quote, :approved)
        q.share_token = nil
        expect(q).not_to be_valid
      end

      it "does not require share_token when voided" do
        q = create(:quote, :voided)
        q.share_token = nil
        expect(q).to be_valid
      end
    end

    describe "voided fields validation" do
      it "requires void_reason and voided_at when voided" do
        q = create(:quote, :voided)
        q.void_reason = nil
        q.voided_at = nil
        expect(q).not_to be_valid
        expect(q.errors[:void_reason]).to include("value_is_mandatory")
        expect(q.errors[:voided_at]).to include("value_is_mandatory")
      end
    end

    describe "approved_at validation" do
      it "requires approved_at when approved" do
        q = create(:quote, :approved)
        q.approved_at = nil
        expect(q).not_to be_valid
        expect(q.errors[:approved_at]).to include("value_is_mandatory")
      end
    end
  end

  describe "callbacks" do
    describe "ensure_number" do
      it "sets number to QT-<year>-<4-digit-seq> on save when blank" do
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

    describe "ensure_share_token" do
      it "assigns a share_token on save when blank" do
        q = build(:quote, share_token: nil)
        q.save!
        expect(q.share_token).to be_present
      end

      it "does not assign a share_token when voided" do
        q = build(:quote, :voided, share_token: nil)
        q.save(validate: false)
        expect(q.share_token).to be_nil
      end
    end
  end
end
