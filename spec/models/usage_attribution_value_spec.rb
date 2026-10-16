# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributionValue do
  subject(:usage_attribution_value) { build(:usage_attribution_value) }

  describe "associations" do
    it do
      expect(usage_attribution_value).to belong_to(:organization)
      expect(usage_attribution_value).to belong_to(:usage_attribution_type)
      expect(usage_attribution_value).to belong_to(:customer)
      expect(usage_attribution_value).to belong_to(:parent).class_name("UsageAttributionValue").optional
      expect(usage_attribution_value).to have_many(:children).class_name("UsageAttributionValue").with_foreign_key(:parent_id).inverse_of(:parent)
    end

    it "still resolves a discarded parent" do
      parent = create(:usage_attribution_value)
      child = create(:usage_attribution_value, organization: parent.organization, customer: parent.customer, parent:)
      parent.discard!

      expect(child.reload.parent).to eq(parent)
    end

    it "still resolves a discarded type and customer" do
      usage_attribution_value.save!
      usage_attribution_value.usage_attribution_type.discard!
      usage_attribution_value.customer.discard!

      reloaded = usage_attribution_value.reload

      expect(reloaded.usage_attribution_type).to be_present
      expect(reloaded.customer).to be_present
    end
  end

  describe "validations" do
    it do
      expect(usage_attribution_value).to validate_presence_of(:value)
      expect(usage_attribution_value).to validate_length_of(:value).is_at_most(255)
    end

    describe "value uniqueness" do
      let(:organization) { create(:organization) }
      let(:customer) { create(:customer, organization:) }
      let(:usage_attribution_type) { create(:usage_attribution_type, organization:) }

      it "rejects the same value for the same customer and type" do
        create(:usage_attribution_value, organization:, customer:, usage_attribution_type:, value: "alice")
        duplicate = build(:usage_attribution_value, organization:, customer:, usage_attribution_type:, value: "alice")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors.where(:value, :taken)).to be_present
      end

      it "allows the same value for another customer" do
        create(:usage_attribution_value, organization:, customer:, usage_attribution_type:, value: "alice")
        other_customer = create(:customer, organization:)

        expect(build(:usage_attribution_value, organization:, customer: other_customer, usage_attribution_type:, value: "alice")).to be_valid
      end

      it "allows the same value under another type" do
        create(:usage_attribution_value, organization:, customer:, usage_attribution_type:, value: "alice")
        other_type = create(:usage_attribution_type, organization:)

        expect(build(:usage_attribution_value, organization:, customer:, usage_attribution_type: other_type, value: "alice")).to be_valid
      end

      it "still rejects the value once the holder is discarded" do
        create(:usage_attribution_value, organization:, customer:, usage_attribution_type:, value: "alice").discard!
        returning = build(:usage_attribution_value, organization:, customer:, usage_attribution_type:, value: "alice")

        expect(returning).not_to be_valid
        expect(returning.errors.where(:value, :taken)).to be_present
      end
    end
  end

  describe "soft deletion" do
    it "hides discarded records behind the default scope" do
      usage_attribution_value.save!
      usage_attribution_value.discard!

      expect(described_class.all).not_to include(usage_attribution_value)
      expect(described_class.with_discarded).to include(usage_attribution_value)
    end

    it "enforces value uniqueness at the database level even once discarded" do
      existing = create(:usage_attribution_value)
      existing.discard!
      duplicate = build(
        :usage_attribution_value,
        organization: existing.organization,
        customer: existing.customer,
        usage_attribution_type: existing.usage_attribution_type,
        value: existing.value
      )

      expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
