# frozen_string_literal: true

require "rails_helper"

RSpec.describe Product do
  subject { build(:product) }

  it_behaves_like "paper_trail traceable"

  it { expect(described_class).to be_soft_deletable }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to have_many(:product_items)
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_presence_of(:name)
      expect(subject).to validate_presence_of(:code)
    end

    describe "code uniqueness" do
      let(:organization) { create(:organization) }
      let(:code) { Faker::Alphanumeric.alphanumeric(number: 10) }

      before { create(:product, organization:, code:) }

      it "validates uniqueness scoped to organization with deleted_at" do
        product = build(:product, organization:, code:)
        expect(product).not_to be_valid
        expect(product.errors[:code]).to include("value_already_exist")
      end

      it "allows same code in different organizations" do
        other_org = create(:organization)
        product = build(:product, organization: other_org, code:)
        expect(product).to be_valid
      end

      it "allows same code when existing record is soft deleted" do
        Product.find_by(organization:, code:).discard
        product = build(:product, organization:, code:)
        expect(product).to be_valid
      end
    end
  end
end
