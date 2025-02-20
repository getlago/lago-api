# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntity, type: :model do
  subject(:billing_entity) { build(:billing_entity) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to belong_to(:organization) }

  it { is_expected.to have_many(:applied_taxes).dependent(:destroy) }
  it { is_expected.to have_many(:taxes).through(:applied_taxes) }

  describe "is_default validation" do
    let(:organization) { create :organization }

    it "validates uniqueness of organization_id for is_default excluding deleted and archived records" do
      deleted_record = create(:billing_entity, :default, :deleted, organization:)
      archived_record = create(:billing_entity, :default, :archived, organization:)
      expect(deleted_record).to be_valid
      expect(archived_record).to be_valid

      record_1 = create(:billing_entity, :default, organization:)
      expect(record_1).to be_valid

      record_2 = build(:billing_entity, :default, organization:)
      expect(record_2).not_to be_valid
      expect(record_2.errors[:is_default]).to include("value_already_exist")

      record_3 = build(:billing_entity, :default)
      expect(record_3).to be_valid
    end
  end
end
