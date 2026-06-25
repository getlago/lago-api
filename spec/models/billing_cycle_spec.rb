# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycle do
  subject(:billing_cycle) { build(:billing_cycle) }

  describe "enums" do
    it do
      expect(subject).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(pending: "pending", processing: "processing", done: "done", failed: "failed")
    end
  end

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:subscription)
      expect(subject).to belong_to(:subscription_product_item)
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_presence_of(:billing_at)
      expect(subject).to validate_presence_of(:period_from)
      expect(subject).to validate_presence_of(:period_to)
    end
  end
end
