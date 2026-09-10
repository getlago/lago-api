# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributionType do
  subject(:usage_attribution_type) { build(:usage_attribution_type) }

  describe "enums" do
    it do
      expect(subject).to define_enum_for(:role)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(hierarchical: "hierarchical", flat: "flat")
    end
  end

  describe "associations" do
    it do
      expect(usage_attribution_type).to belong_to(:organization)
      expect(usage_attribution_type).to belong_to(:parent).class_name("UsageAttributionType").optional
      expect(usage_attribution_type).to have_many(:children).class_name("UsageAttributionType").with_foreign_key(:parent_id).inverse_of(:parent)
    end
  end

  describe "validations" do
    it do
      expect(usage_attribution_type).to validate_presence_of(:code)
      expect(usage_attribution_type).to validate_presence_of(:attribution_key)
      expect(usage_attribution_type).to validate_length_of(:code).is_at_most(255)
      expect(usage_attribution_type).to validate_length_of(:name).is_at_most(255)
      expect(usage_attribution_type).to validate_length_of(:attribution_key).is_at_most(255)
    end

    describe "code uniqueness" do
      let(:organization) { create(:organization) }

      it "rejects a duplicate code within the organization" do
        create(:usage_attribution_type, organization:, code: "user")
        duplicate = build(:usage_attribution_type, organization:, code: "user")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end

      it "allows the same code in another organization" do
        create(:usage_attribution_type, organization:, code: "user")

        expect(build(:usage_attribution_type, organization: create(:organization), code: "user")).to be_valid
      end

      it "frees the code once the holder is discarded" do
        create(:usage_attribution_type, organization:, code: "user").discard!

        expect(build(:usage_attribution_type, organization:, code: "user")).to be_valid
      end
    end

    describe "attribution_key uniqueness" do
      let(:organization) { create(:organization) }

      it "rejects two types resolving from the same event property" do
        create(:usage_attribution_type, organization:, attribution_key: "user_id")
        duplicate = build(:usage_attribution_type, organization:, attribution_key: "user_id")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors.where(:attribution_key, :taken)).to be_present
      end

      it "allows the same attribution_key in another organization" do
        create(:usage_attribution_type, organization:, attribution_key: "user_id")

        expect(build(:usage_attribution_type, organization: create(:organization), attribution_key: "user_id")).to be_valid
      end

      it "frees the attribution_key once the holder is discarded" do
        create(:usage_attribution_type, organization:, attribution_key: "user_id").discard!

        expect(build(:usage_attribution_type, organization:, attribution_key: "user_id")).to be_valid
      end
    end

    describe "parent_id validation" do
      let(:organization) { create(:organization) }
      let(:department) { create(:usage_attribution_type, organization:, code: "department") }

      it "accepts a hierarchical parent from the same organization" do
        expect(build(:usage_attribution_type, organization:, parent: department)).to be_valid
      end

      it "accepts no parent at all" do
        expect(build(:usage_attribution_type, organization:, parent: nil)).to be_valid
        expect(build(:flat_usage_attribution_type, organization:, parent: nil)).to be_valid
      end

      it "rejects a parent on a flat type" do
        flat = build(:flat_usage_attribution_type, organization:, parent: department)

        expect(flat).not_to be_valid
        expect(flat.errors.where(:parent_id, :forbidden_for_flat_role)).to be_present
      end

      it "rejects a flat parent" do
        flat = create(:flat_usage_attribution_type, organization:)
        child = build(:usage_attribution_type, organization:, parent: flat)

        expect(child).not_to be_valid
        expect(child.errors.where(:parent_id, :must_be_hierarchical)).to be_present
      end

      it "rejects a parent from another organization" do
        foreign = create(:usage_attribution_type, organization: create(:organization))
        child = build(:usage_attribution_type, organization:, parent: foreign)

        expect(child).not_to be_valid
        expect(child.errors.where(:parent_id, :must_belong_to_same_organization)).to be_present
      end

      it "rejects itself as parent" do
        department.parent = department

        expect(department).not_to be_valid
        expect(department.errors.where(:parent_id, :cannot_form_a_cycle)).to be_present
      end

      it "rejects a cycle through an ancestor" do
        team = create(:usage_attribution_type, organization:, code: "team", parent: department)
        user = create(:usage_attribution_type, organization:, code: "user", parent: team)
        department.parent = user

        expect(department).not_to be_valid
        expect(department.errors.where(:parent_id, :cannot_form_a_cycle)).to be_present
      end
    end
  end

  describe "soft deletion" do
    it "hides discarded records behind the default scope" do
      usage_attribution_type.save!
      usage_attribution_type.discard!

      expect(described_class.all).not_to include(usage_attribution_type)
      expect(described_class.with_discarded).to include(usage_attribution_type)
    end

    it "enforces code uniqueness among kept rows at the database level" do
      organization = create(:organization)
      create(:usage_attribution_type, organization:, code: "user")
      duplicate = build(:usage_attribution_type, organization:, code: "user")

      expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "enforces attribution_key uniqueness among kept rows at the database level" do
      organization = create(:organization)
      create(:usage_attribution_type, organization:, attribution_key: "user_id")
      duplicate = build(:usage_attribution_type, organization:, attribution_key: "user_id")

      expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
